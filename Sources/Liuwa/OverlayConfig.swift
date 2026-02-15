import AppKit
import Speech

final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()

    @MainActor static var cachedTranscriptionLocales: [(id: String, name: String)]?

    @MainActor static func fetchSupportedLocales() async {
        let supported = await SpeechTranscriber.supportedLocales
        var result: [(String, String)] = []
        for loc in supported {
            let name = Locale.current.localizedString(forIdentifier: loc.identifier) ?? loc.identifier
            result.append((loc.identifier, name))
        }
        result.sort { $0.1 < $1.1 }
        cachedTranscriptionLocales = result
    }

    // Appearance
    var width: CGFloat = 380
    var heightRatio: CGFloat = 0.8
    var marginRight: CGFloat = 24
    var transparency: CGFloat = 0.75
    var cornerRadius: CGFloat = 12
    var fontSize: CGFloat = 10
    var fontName: String = ""

    // Layout
    var transcriptionRatio: CGFloat = 0.25
    var docRatio: CGFloat = 0.25

    // LLM
    static let llmProviders = ["local", "openai", "anthropic", "gemini", "ollama"]
    static let llmProviderLabels = ["Local (Apple AI)", "OpenAI", "Anthropic (Claude)", "Google Gemini", "Ollama"]
    var llmProvider: String = "local"
    var remoteAPIKey: String = ""
    var remoteModel: String = ""
    var remoteEndpoint: String = ""
    var responseLanguage: String = "English"
    var transcriptionLocale: String = "en_US"

    // Screen capture
    var sendScreenText: Bool = true
    var sendScreenshot: Bool = false
    var screenshotMode: String = "auto" // "auto", "ocr", "image"

    // Documents
    var docsDirectory: String = NSString("~/Documents/Liuwa").expandingTildeInPath
    var attachDocToContext: Bool = true
    var docsVisible: Bool = false

    // Presets
    var presets: [(label: String, prompt: String)] = [
        ("Reply", "Based on the conversation, suggest how I should reply to the last question or topic."),
        ("Summarize", "Concisely summarize the key points of the conversation so far."),
        ("Solve", "Based on the on-screen problem and conversation, provide the approach and key code."),
        ("Improve", "Improve and polish the following text. Fix grammar, clarity, and tone."),
    ]

    // Hotkeys
    var hotkeyBindings: [String: String] = defaultHotkeyBindings

    static let defaultHotkeyBindings: [String: String] = [
        "toggleOverlay": "O", "toggleGhost": "G", "toggleClickThrough": "E",
        "toggleTranscription": "T", "toggleSystemAudio": "Y", "clearTranscription": "W",
        "showDocs": "D", "toggleAttachDoc": "A", "openSettings": "S",
        "cycleScreenText": "X", "cycleScreenshot": "Z", "clearAI": "C",
        "scrollAIUp": "↑", "scrollAIDown": "↓",
        "scrollDocUp": "I", "scrollDocDown": "K", "docPrev": "J", "docNext": "L",
        "preset1": "1", "preset2": "2", "preset3": "3", "preset4": "4",
        "quit": "Q",
    ]

    func keyFor(_ action: String) -> String { hotkeyBindings[action] ?? "?" }

    // Colors
    var textColor: NSColor { .white }
    var dimColor: NSColor { NSColor(white: 1.0, alpha: 0.6) }
    var accentColor: NSColor { NSColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0) }
    var bgColor: NSColor { NSColor(white: 0.0, alpha: transparency * 0.85) }

    var font: NSFont {
        if fontName.isEmpty { return .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
        return NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
    var headerFont: NSFont { .systemFont(ofSize: fontSize, weight: .bold) }

    private let configPath = NSString("~/.liuwa/config.json").expandingTildeInPath

    private init() {
        let fm = FileManager.default
        let dir = NSString("~/.liuwa").expandingTildeInPath
        if !fm.fileExists(atPath: dir) { try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }
        if !fm.fileExists(atPath: docsDirectory) { try? fm.createDirectory(atPath: docsDirectory, withIntermediateDirectories: true) }
        load()
    }

    func load() {
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let v = json["width"] as? CGFloat { width = v }
        if let v = json["height_ratio"] as? CGFloat { heightRatio = v }
        if let v = json["margin_right"] as? CGFloat { marginRight = v }
        if let v = json["transparency"] as? CGFloat { transparency = v }
        if let v = json["corner_radius"] as? CGFloat { cornerRadius = v }
        if let v = json["font_size"] as? CGFloat { fontSize = v }
        if let v = json["font_name"] as? String { fontName = v }
        if let v = json["transcription_ratio"] as? CGFloat { transcriptionRatio = v }
        if let v = json["doc_ratio"] as? CGFloat { docRatio = v }
        if let v = json["api_key"] as? String { remoteAPIKey = v }
        if let v = json["model"] as? String { remoteModel = v }
        if let v = json["endpoint"] as? String { remoteEndpoint = v }
        if let v = json["llm_provider"] as? String { llmProvider = v }
        if let v = json["response_language"] as? String { responseLanguage = v }
        if let v = json["transcription_locale"] as? String {
            transcriptionLocale = v.replacingOccurrences(of: "-", with: "_")
        }
        if let v = json["send_screen_text"] as? Bool { sendScreenText = v }
        if let v = json["send_screenshot"] as? Bool { sendScreenshot = v }
        if let v = json["screenshot_mode"] as? String { screenshotMode = v }
        if let v = json["docs_directory"] as? String { docsDirectory = v }
        if let v = json["attach_doc_to_context"] as? Bool { attachDocToContext = v }
        if let v = json["docs_visible"] as? Bool { docsVisible = v }
        if let arr = json["presets"] as? [[String: String]] {
            var loaded: [(String, String)] = []
            for item in arr { if let l = item["label"], let p = item["prompt"] { loaded.append((l, p)) } }
            while loaded.count < 4 { loaded.append(("Preset \(loaded.count+1)", "")) }
            presets = Array(loaded.prefix(4))
        }
        if let hk = json["hotkey_bindings"] as? [String: String] {
            var merged = Self.defaultHotkeyBindings
            for (k, v) in hk { merged[k] = v }
            hotkeyBindings = merged
        }
    }

    func save() {
        let presetArr = presets.map { ["label": $0.label, "prompt": $0.prompt] }
        let json: [String: Any] = [
            "width": width, "height_ratio": heightRatio, "margin_right": marginRight,
            "transparency": transparency, "corner_radius": cornerRadius,
            "font_size": fontSize, "font_name": fontName,
            "transcription_ratio": transcriptionRatio, "doc_ratio": docRatio,
            "api_key": remoteAPIKey, "model": remoteModel, "endpoint": remoteEndpoint,
            "llm_provider": llmProvider, "response_language": responseLanguage,
            "transcription_locale": transcriptionLocale,
            "send_screen_text": sendScreenText, "send_screenshot": sendScreenshot,
            "screenshot_mode": screenshotMode,
            "docs_directory": docsDirectory, "attach_doc_to_context": attachDocToContext, "docs_visible": docsVisible,
            "presets": presetArr, "hotkey_bindings": hotkeyBindings,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            FileManager.default.createFile(atPath: configPath, contents: data)
        }
    }
}
