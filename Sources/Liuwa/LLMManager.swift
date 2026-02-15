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

    private func buildModel() -> (any LanguageModel)? {
        let s = AppSettings.shared
        let model = s.remoteModel
        guard !model.isEmpty || s.llmProvider == "local" else { return nil }

        switch s.llmProvider {
        case "local":
            if case .available = SystemLanguageModel.default.availability {
                return SystemLanguageModel.default
            }
            return nil
        case "openai":
            guard !s.remoteAPIKey.isEmpty else { return nil }
            if !s.remoteEndpoint.isEmpty {
                return OpenAILanguageModel(
                    baseURL: URL(string: s.remoteEndpoint)!,
                    apiKey: s.remoteAPIKey,
                    model: model
                )
            }
            return OpenAILanguageModel(apiKey: s.remoteAPIKey, model: model)
        case "anthropic":
            guard !s.remoteAPIKey.isEmpty else { return nil }
            return AnthropicLanguageModel(apiKey: s.remoteAPIKey, model: model)
        case "gemini":
            guard !s.remoteAPIKey.isEmpty else { return nil }
            return GeminiLanguageModel(apiKey: s.remoteAPIKey, model: model)
        case "ollama":
            let base = s.remoteEndpoint.isEmpty ? "http://localhost:11434" : s.remoteEndpoint
            return OllamaLanguageModel(baseURL: URL(string: base)!, model: model)
        default:
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
    }

    private func queryLLM(prompt: String, image: CGImage? = nil) async throws {
        if session == nil { setupSession() }
        guard let session else {
            conversationLog += "No LLM configured. ⌘⌥S to set up.\n\n"
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
