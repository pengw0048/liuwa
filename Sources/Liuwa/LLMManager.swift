import Foundation
import AppKit
import FoundationModels

@MainActor
final class LLMManager {
    private weak var overlay: OverlayController?
    weak var screenCapture: ScreenCaptureManager?
    private var localSession: LanguageModelSession?
    private var currentTask: Task<Void, Never>?
    private var conversationLog: String = ""
    private var queryCount: Int = 0

    init(overlay: OverlayController, transcription: TranscriptionManager) {
        self.overlay = overlay; setupLocalSession()
    }

    func reloadConfig() { AppSettings.shared.load(); setupLocalSession() }

    func clearConversation() {
        currentTask?.cancel(); conversationLog = ""; queryCount = 0; setupLocalSession()
    }

    func sendPresetQuery(_ instruction: String) {
        guard !instruction.isEmpty else { return }
        currentTask?.cancel(); queryCount += 1
        let s = AppSettings.shared

        conversationLog += "── #\(queryCount) ──\n"
        overlay?.setText(conversationLog + "…", for: .aiResponse)

        currentTask = Task {
            // Auto-capture if either screen mode is on
            if s.sendScreenText || s.sendScreenshot { await screenCapture?.capture() }

            let ctx = gatherContext()
            if ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                conversationLog += "(no context)\n\n"; overlay?.setText(conversationLog, for: .aiResponse); return
            }

            let summary = summarizeContext(ctx)
            conversationLog += "\(summary)\n"
            overlay?.setText(conversationLog + "Generating…", for: .aiResponse)

            let prompt = "Respond in \(s.responseLanguage).\n\n【Instruction】\n\(instruction)\n\n\(ctx)"
            do { try await queryLLM(prompt: prompt) }
            catch { if !Task.isCancelled { conversationLog += "Error: \(error.localizedDescription)\n\n"; overlay?.setText(conversationLog, for: .aiResponse) } }
        }
    }

    private func summarizeContext(_ c: String) -> String {
        var p = [String]()
        if c.contains("【Transcript】") { p.append("transcript") }
        if c.contains("【Screen】") { p.append("screen") }
        if c.contains("【Docs】") { p.append("docs") }
        return "ctx: " + (p.isEmpty ? "none" : p.joined(separator: "+"))
    }

    private func gatherContext() -> String {
        var c = ""
        if let t = overlay?.getPanelContent(.transcription), !t.isEmpty { c += "【Transcript】\n\(t)\n\n" }
        if let sc = screenCapture?.lastCapturedText, !sc.isEmpty { c += "【Screen】\n\(sc)\n\n" }
        if let d = overlay?.getPanelContent(.documents), !d.isEmpty { c += "【Docs】\n\(d)\n\n" }
        return c
    }

    private func queryLLM(prompt: String) async throws {
        let s = AppSettings.shared
        if s.useLocalModel, case .available = SystemLanguageModel.default.availability {
            try await streamLocal(prompt: prompt); return
        }
        if !s.remoteAPIKey.isEmpty { try await streamRemote(prompt: prompt); return }
        conversationLog += "No LLM. ⌘⌥S to configure.\n\n"; overlay?.setText(conversationLog, for: .aiResponse)
    }

    private func setupLocalSession() {
        guard case .available = SystemLanguageModel.default.availability else { return }
        let s = AppSettings.shared
        localSession = LanguageModelSession(instructions: "You are a helpful meeting/interview assistant. Analyze context and give concise actionable advice. For coding: provide approach and key code. Respond in \(s.responseLanguage).")
    }

    private func streamLocal(prompt: String) async throws {
        if localSession == nil { setupLocalSession() }
        guard let session = localSession else { throw LLMError.localUnavailable }
        var acc = ""
        for try await snap in session.streamResponse(to: prompt) {
            acc = snap.content; overlay?.setText(conversationLog + acc + "\n", for: .aiResponse)
        }
        if acc.isEmpty { acc = "(no response)" }
        conversationLog += acc + "\n\n"; overlay?.setText(conversationLog, for: .aiResponse)
    }

    private func streamRemote(prompt: String) async throws {
        let s = AppSettings.shared
        guard let url = URL(string: s.remoteEndpoint) else { throw LLMError.invalidEndpoint }
        let sysPr = "You are a helpful meeting/interview assistant. Analyze context, give concise actionable advice. For coding: approach + key code. Respond in \(s.responseLanguage)."
        let body: [String: Any] = ["model": s.remoteModel, "messages": [["role":"system","content":sysPr],["role":"user","content":prompt]], "max_tokens": 2048, "temperature": 0.7, "stream": true]
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(s.remoteAPIKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body); req.timeoutInterval = 120

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            var d = Data(); for try await b in bytes { d.append(b) }
            throw LLMError.apiError(statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0, message: String(data: d, encoding: .utf8) ?? "")
        }
        var acc = ""
        for try await line in bytes.lines {
            guard !Task.isCancelled, line.hasPrefix("data: ") else { if line.hasPrefix("data: ") { continue } else { continue } }
            let j = String(line.dropFirst(6)); guard j != "[DONE]" else { break }
            guard let data = j.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
                  let ch = json["choices"] as? [[String:Any]], let delta = ch.first?["delta"] as? [String:Any],
                  let content = delta["content"] as? String else { continue }
            acc += content; overlay?.setText(conversationLog + acc, for: .aiResponse)
        }
        if acc.isEmpty { acc = "(no response)" }
        conversationLog += acc + "\n\n"; overlay?.setText(conversationLog, for: .aiResponse)
    }
}

enum LLMError: Error, LocalizedError {
    case localUnavailable, invalidEndpoint, networkError, parseError
    case apiError(statusCode: Int, message: String)
    var errorDescription: String? {
        switch self {
        case .localUnavailable: "Foundation Models unavailable"
        case .invalidEndpoint: "Invalid API endpoint"
        case .networkError: "Network error"
        case .apiError(let c, let m): "API error (\(c)): \(m)"
        case .parseError: "Parse error"
        }
    }
}
