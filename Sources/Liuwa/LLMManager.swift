import Foundation
import AppKit
import AnyLanguageModel

@MainActor
final class LLMManager {
    private weak var overlay: OverlayController?
    weak var screenCapture: ScreenCaptureManager?
    weak var docs: DocumentManager?
    private var session: LanguageModelSession?
    private var currentTask: Task<Void, Never>?
    private var conversationLog: String = ""
    private var queryCount: Int = 0

    init(overlay: OverlayController) {
        self.overlay = overlay; setupSession()
    }

    func reloadConfig() { AppSettings.shared.load(); setupSession() }

    func clearConversation() {
        currentTask?.cancel(); conversationLog = ""; queryCount = 0; setupSession()
    }

    func sendPresetQuery(_ instruction: String) {
        guard !instruction.isEmpty else { return }
        currentTask?.cancel(); queryCount += 1
        let s = AppSettings.shared

        conversationLog += "── #\(queryCount) ──\n"
        overlay?.setText(conversationLog + "…", for: .aiResponse)

        currentTask = Task {
            if s.sendScreenText || s.sendScreenshot { await screenCapture?.capture() }

            let ctx = gatherContext()
            if ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                conversationLog += "(no context)\n\n"; overlay?.setText(conversationLog, for: .aiResponse); return
            }

            let summary = summarizeContext(ctx)
            conversationLog += "\(summary)\n"
            overlay?.setText(conversationLog + "Generating…", for: .aiResponse)

            let prompt = "Respond in \(s.responseLanguage).\n\n【Instruction】\n\(instruction)\n\n\(ctx)"

            // Determine whether to send image directly
            let image: CGImage? = shouldSendImage() ? screenCapture?.lastCapturedImage : nil

            do { try await queryLLM(prompt: prompt, image: image) }
            catch { if !Task.isCancelled { conversationLog += "Error: \(error.localizedDescription)\n\n"; overlay?.setText(conversationLog, for: .aiResponse) } }
        }
    }

    private func shouldSendImage() -> Bool {
        let s = AppSettings.shared
        guard s.sendScreenshot, screenCapture?.lastCapturedImage != nil else { return false }
        switch s.screenshotMode {
        case "image": return true
        case "ocr": return false
        default: // "auto" — send image to API models, OCR for local
            return s.llmProvider != "local"
        }
    }

    private func summarizeContext(_ c: String) -> String {
        var p = [String]()
        if c.contains("【Transcript】") { p.append("transcript") }
        if c.contains("【Screen】") { p.append("screen") }
        if c.contains("【Document】") { p.append("doc") }
        return "ctx: " + (p.isEmpty ? "none" : p.joined(separator: "+"))
    }

    private func gatherContext() -> String {
        var c = ""

        // Transcript — WYSIWYG: read exactly what's displayed in the panel
        if let t = overlay?.getPanelContent(.transcription), !t.isEmpty {
            c += "【Transcript】\n\(t)\n\n"
        }

        // Screen
        if let sc = screenCapture?.lastCapturedText, !sc.isEmpty { c += "【Screen】\n\(sc)\n\n" }

        // Document (if attach is enabled)
        if AppSettings.shared.attachDocToContext, let docText = docs?.currentDocContent, !docText.isEmpty {
            let docName = docs?.currentDocName ?? "doc"
            c += "【Document: \(docName)】\n\(docText)\n\n"
        }

        return c
    }

    // MARK: - Model & Session Setup

    private var lastSetupError: String = ""

    private func buildModel() -> (any LanguageModel)? {
        let s = AppSettings.shared
        let model = s.remoteModel
        lastSetupError = ""

        switch s.llmProvider {
        case "local":
            let availability = SystemLanguageModel.default.availability
            if case .available = availability {
                return SystemLanguageModel.default
            }
            lastSetupError = "Local model not available (availability: \(availability)). Apple Silicon with macOS 26+ required. Check Settings > Apple Intelligence."
            return nil
        case "openai":
            guard !s.remoteAPIKey.isEmpty else { lastSetupError = "OpenAI API key not set. ⌘⌥S to configure."; return nil }
            guard !model.isEmpty else { lastSetupError = "OpenAI model not set (e.g. gpt-4o-mini). ⌘⌥S to configure."; return nil }
            if !s.remoteEndpoint.isEmpty {
                return OpenAILanguageModel(
                    baseURL: URL(string: s.remoteEndpoint)!,
                    apiKey: s.remoteAPIKey,
                    model: model
                )
            }
            return OpenAILanguageModel(apiKey: s.remoteAPIKey, model: model)
        case "anthropic":
            guard !s.remoteAPIKey.isEmpty else { lastSetupError = "Anthropic API key not set. ⌘⌥S to configure."; return nil }
            guard !model.isEmpty else { lastSetupError = "Anthropic model not set (e.g. claude-sonnet-4-20250514). ⌘⌥S to configure."; return nil }
            return AnthropicLanguageModel(apiKey: s.remoteAPIKey, model: model)
        case "gemini":
            guard !s.remoteAPIKey.isEmpty else { lastSetupError = "Gemini API key not set. ⌘⌥S to configure."; return nil }
            guard !model.isEmpty else { lastSetupError = "Gemini model not set (e.g. gemini-2.0-flash). ⌘⌥S to configure."; return nil }
            return GeminiLanguageModel(apiKey: s.remoteAPIKey, model: model)
        case "ollama":
            guard !model.isEmpty else { lastSetupError = "Ollama model not set (e.g. llama3). ⌘⌥S to configure."; return nil }
            let base = s.remoteEndpoint.isEmpty ? "http://localhost:11434" : s.remoteEndpoint
            return OllamaLanguageModel(baseURL: URL(string: base)!, model: model)
        default:
            lastSetupError = "Unknown LLM provider: \(s.llmProvider)"
            return nil
        }
    }

    private func setupSession() {
        guard let model = buildModel() else { session = nil; return }
        let s = AppSettings.shared
        session = LanguageModelSession(
            model: model,
            instructions: "You are a helpful meeting/interview assistant. Analyze context and give concise actionable advice. For coding: provide approach and key code. Respond in \(s.responseLanguage)."
        )
        lastSetupError = ""  // clear error on success
    }

    private func queryLLM(prompt: String, image: CGImage? = nil) async throws {
        if session == nil { setupSession() }
        guard let session else {
            let reason = lastSetupError.isEmpty ? "No LLM configured. ⌘⌥S to set up." : "⚠️ \(lastSetupError)"
            conversationLog += "\(reason)\n\n"
            overlay?.setText(conversationLog, for: .aiResponse)
            return
        }

        var acc = ""
        if let image {
            // Send image directly to vision-capable model
            let imageSegment = try Transcript.ImageSegment(image: image)
            for try await snap in session.streamResponse(to: prompt, image: imageSegment) {
                acc = snap.content
                overlay?.setText(conversationLog + acc + "\n", for: .aiResponse)
            }
        } else {
            for try await snap in session.streamResponse(to: prompt) {
                acc = snap.content
                overlay?.setText(conversationLog + acc + "\n", for: .aiResponse)
            }
        }
        if acc.isEmpty { acc = "(no response)" }
        conversationLog += acc + "\n\n"
        overlay?.setText(conversationLog, for: .aiResponse)
    }
}
