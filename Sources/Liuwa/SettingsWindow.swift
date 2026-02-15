import AppKit

/// Settings window with Save / Cancel buttons and hotkey configuration.
@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    var onChanged: (() -> Void)?
    var onLivePreview: (() -> Void)?
    private var handler: SettingsHandler?
    private var snapshot: SettingsSnapshot?

    func toggle() {
        if let w = window, w.isVisible { cancel(); return }
        show()
    }

    func rebuild() {
        let pos = window?.frame.origin
        window?.close(); window = nil; handler = nil
        show()
        if let pos { window?.setFrameOrigin(pos) }
    }

    private func cancel() {
        if let snap = snapshot { snap.restore() }
        onChanged?()
        window?.close(); window = nil; handler = nil; snapshot = nil
    }

    fileprivate func commitAndClose() {
        snapshot = nil
        onChanged?()
        window?.close(); window = nil; handler = nil
    }

    fileprivate func revertAndClose() { cancel() }

    private func show() {
        let s = AppSettings.shared
        snapshot = SettingsSnapshot(s)

        let W: CGFloat = 480
        let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: W - 16, height: 1400))
        var y: CGFloat = 8
        let lx: CGFloat = 12, fx: CGFloat = 140, fw: CGFloat = 290

        func sec(_ t: String) {
            if y > 12 { y += 4 }
            let l = NSTextField(labelWithString: t); l.font = .systemFont(ofSize: 11, weight: .bold)
            l.frame = NSRect(x: lx, y: y, width: 300, height: 14); doc.addSubview(l); y += 17
        }
        func lbl(_ t: String) {
            let l = NSTextField(labelWithString: t); l.font = .systemFont(ofSize: 11)
            l.frame = NSRect(x: lx, y: y+2, width: 124, height: 14); doc.addSubview(l)
        }
        func vlbl(_ v: String) -> NSTextField {
            let l = NSTextField(labelWithString: v); l.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            l.frame = NSRect(x: fx+fw+4, y: y+2, width: 44, height: 14); doc.addSubview(l); return l
        }
        func slider(_ v: Double, _ mn: Double, _ mx: Double) -> NSSlider {
            let sl = NSSlider(value: v, minValue: mn, maxValue: mx, target: nil, action: nil)
            sl.frame = NSRect(x: fx, y: y, width: fw, height: 18); doc.addSubview(sl); return sl
        }

        // ── Appearance ──
        sec("Appearance")
        lbl("Transparency:"); let trSl = slider(Double(s.transparency), 0.15, 1.0); let trV = vlbl(String(format: "%.0f%%", s.transparency*100)); y += 20
        lbl("Width:"); let wdSl = slider(Double(s.width), 250, 600); let wdV = vlbl(String(format: "%.0f", s.width)); y += 20
        lbl("Font Size:"); let fsSl = slider(Double(s.fontSize), 9, 18); let fsV = vlbl(String(format: "%.0f", s.fontSize)); y += 20

        // ── LLM ──
        sec("LLM")
        lbl("Provider:")
        let providerP = NSPopUpButton(frame: NSRect(x: fx, y: y-2, width: 180, height: 20))
        for label in AppSettings.llmProviderLabels { providerP.addItem(withTitle: label) }
        if let idx = AppSettings.llmProviders.firstIndex(of: s.llmProvider) { providerP.selectItem(at: idx) }
        providerP.font = .systemFont(ofSize: 11); doc.addSubview(providerP); y += 24

        let needsKey = (s.llmProvider == "openai" || s.llmProvider == "anthropic" || s.llmProvider == "gemini")
        let needsModel = (s.llmProvider != "local")
        let needsEndpoint = (s.llmProvider == "openai" || s.llmProvider == "ollama")

        var keyF: NSTextField?
        var modF: NSTextField?
        var endF: NSTextField?

        if needsKey {
            lbl("API Key:")
            let k = NSTextField(string: s.remoteAPIKey)
            k.frame = NSRect(x: fx, y: y, width: fw, height: 18)
            k.font = .systemFont(ofSize: 11)
            switch s.llmProvider {
            case "anthropic": k.placeholderString = "sk-ant-..."
            case "gemini": k.placeholderString = "AIza..."
            default: k.placeholderString = "sk-..."
            }
            doc.addSubview(k); keyF = k; y += 20
        }

        if needsModel {
            lbl("Model:")
            let m = NSTextField(string: s.remoteModel)
            m.frame = NSRect(x: fx, y: y, width: fw, height: 18)
            m.font = .systemFont(ofSize: 11)
            switch s.llmProvider {
            case "openai": m.placeholderString = "e.g. gpt-4o-mini"
            case "anthropic": m.placeholderString = "e.g. claude-sonnet-4-5-20250929"
            case "gemini": m.placeholderString = "e.g. gemini-2.0-flash"
            case "ollama": m.placeholderString = "e.g. llama3.2"
            default: break
            }
            doc.addSubview(m); modF = m; y += 20
        }

        if needsEndpoint {
            lbl("Endpoint:")
            let e = NSTextField(string: s.remoteEndpoint)
            e.frame = NSRect(x: fx, y: y, width: fw, height: 18)
            e.font = .systemFont(ofSize: 11)
            switch s.llmProvider {
            case "openai": e.placeholderString = "(leave empty for api.openai.com)"
            case "ollama": e.placeholderString = "http://localhost:11434"
            default: break
            }
            doc.addSubview(e); endF = e; y += 22
        }

        lbl("Response language:")
        let langCB = NSComboBox(frame: NSRect(x: fx, y: y-2, width: 160, height: 22))
        langCB.isEditable = true; langCB.completes = true
        for l in ["English","Chinese","Japanese","Korean","Spanish","French","German","Arabic","Portuguese","Russian","Hindi"] { langCB.addItem(withObjectValue: l) }
        langCB.stringValue = s.responseLanguage
        langCB.font = .systemFont(ofSize: 11); doc.addSubview(langCB); y += 24

        // ── Transcription ──
        sec("Transcription")
        lbl("Language:")
        let transLocP = NSPopUpButton(frame: NSRect(x: fx, y: y-2, width: 220, height: 20))
        let locales = Self.transcriptionLocales()
        for (id, name) in locales { transLocP.addItem(withTitle: "\(name) (\(id))") }
        if let idx = locales.firstIndex(where: { $0.id == s.transcriptionLocale }) { transLocP.selectItem(at: idx) }
        else { transLocP.addItem(withTitle: s.transcriptionLocale); transLocP.selectItem(at: transLocP.numberOfItems - 1) }
        transLocP.font = .systemFont(ofSize: 11); doc.addSubview(transLocP); y += 22

        // ── Screen Capture ──
        sec("Screen Capture")
        let txtChk = NSButton(checkboxWithTitle: "Send text (Accessibility)", target: nil, action: nil)
        txtChk.state = s.sendScreenText ? .on : .off; txtChk.frame = NSRect(x: fx, y: y, width: 300, height: 16); doc.addSubview(txtChk); y += 19
        let imgChk = NSButton(checkboxWithTitle: "Send screenshot", target: nil, action: nil)
        imgChk.state = s.sendScreenshot ? .on : .off; imgChk.frame = NSRect(x: fx, y: y, width: 300, height: 16); doc.addSubview(imgChk); y += 19

        lbl("Screenshot mode:")
        let ssP = NSPopUpButton(frame: NSRect(x: fx, y: y-2, width: 160, height: 20))
        ssP.addItem(withTitle: "Auto (local=OCR, API=image)")
        ssP.addItem(withTitle: "Always OCR")
        ssP.addItem(withTitle: "Always send image")
        let ssModes = ["auto", "ocr", "image"]
        if let idx = ssModes.firstIndex(of: s.screenshotMode) { ssP.selectItem(at: idx) }
        ssP.font = .systemFont(ofSize: 10); doc.addSubview(ssP); y += 22

        // ── Documents ──
        sec("Documents")
        lbl("Directory:")
        let docField = NSTextField(string: s.docsDirectory); docField.frame = NSRect(x: fx, y: y, width: fw-54, height: 18); docField.font = .systemFont(ofSize: 10); doc.addSubview(docField)
        let brBtn = NSButton(title: "Browse…", target: nil, action: nil); brBtn.frame = NSRect(x: fx+fw-50, y: y-1, width: 54, height: 20); brBtn.font = .systemFont(ofSize: 10); doc.addSubview(brBtn); y += 22

        let attachChk = NSButton(checkboxWithTitle: "Attach current doc to AI context", target: nil, action: nil)
        attachChk.state = s.attachDocToContext ? .on : .off; attachChk.frame = NSRect(x: fx, y: y, width: 300, height: 16); doc.addSubview(attachChk); y += 20

        // ── Presets ──
        sec("AI Presets (⌘⌥ 1-4)")
        var pLF = [NSTextField](), pPF = [NSTextField]()
        for i in 0..<4 {
            let p = s.presets[safe: i]
            lbl("⌘⌥\(i+1):")
            let lf = NSTextField(string: p?.label ?? ""); lf.frame = NSRect(x: fx, y: y, width: 66, height: 18); lf.placeholderString = "Label"; lf.font = .systemFont(ofSize: 11); doc.addSubview(lf); pLF.append(lf)
            let pf = NSTextField(string: p?.prompt ?? ""); pf.frame = NSRect(x: fx+72, y: y, width: fw-72, height: 18); pf.placeholderString = "Prompt"; pf.font = .systemFont(ofSize: 10); doc.addSubview(pf); pPF.append(pf); y += 21
        }

        // ── Hotkeys ──
        sec("Hotkeys (all ⌘⌥ + key)")
        let hotkeyDefs: [(action: String, label: String)] = [
            ("toggleOverlay", "👁‍🗨 Show/Hide"),
            ("toggleGhost", "👻 Ghost"),
            ("toggleClickThrough", "🖱 Click-through"),
            ("openSettings", "⚙ Settings"),
            ("toggleTranscription", "🎤 Mic"),
            ("toggleSystemAudio", "🔊 System Audio"),
            ("clearTranscription", "🗑 Clear Transcript"),
            ("cycleScreenText", "📝 Screen Text"),
            ("cycleScreenshot", "📷 Screenshot"),
            ("preset1", "1️⃣ Preset 1"),
            ("preset2", "2️⃣ Preset 2"),
            ("preset3", "3️⃣ Preset 3"),
            ("preset4", "4️⃣ Preset 4"),
            ("clearAI", "🧹 Clear AI"),
            ("showDocs", "📂 Documents"),
            ("scrollDocUp", "📄⬆ Doc Scroll Up"),
            ("scrollDocDown", "📄⬇ Doc Scroll Down"),
            ("toggleAttachDoc", "📎 Attach Doc"),
            ("quit", "❌ Quit"),
        ]

        let colW: CGFloat = (W - 40) / 2
        var hkFields: [(String, NSTextField)] = []
        var col = 0
        for def in hotkeyDefs {
            let cx = lx + CGFloat(col) * colW
            let descL = NSTextField(labelWithString: def.label)
            descL.font = .systemFont(ofSize: 10); descL.textColor = .labelColor
            descL.frame = NSRect(x: cx, y: y + 1, width: 110, height: 14); doc.addSubview(descL)

            let kf = NSTextField(string: s.hotkeyBindings[def.action] ?? "")
            kf.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            kf.alignment = .center
            kf.frame = NSRect(x: cx + 112, y: y, width: 30, height: 18)
            doc.addSubview(kf)
            hkFields.append((def.action, kf))

            col += 1
            if col >= 2 { col = 0; y += 20 }
        }
        if col != 0 { y += 20 }

        let arrowL = NSTextField(labelWithString: "↑↓ Scroll AI, ←→ Switch docs (fixed)")
        arrowL.font = .systemFont(ofSize: 10); arrowL.textColor = .secondaryLabelColor
        arrowL.frame = NSRect(x: lx, y: y, width: 260, height: 14); doc.addSubview(arrowL); y += 18

        // ── Save / Cancel ──
        y += 8
        let saveBtn = NSButton(title: "Save", target: nil, action: nil)
        saveBtn.frame = NSRect(x: W - 16 - 80, y: y, width: 72, height: 24)
        saveBtn.bezelStyle = .rounded; saveBtn.keyEquivalent = "\r"
        doc.addSubview(saveBtn)

        let cancelBtn = NSButton(title: "Cancel", target: nil, action: nil)
        cancelBtn.frame = NSRect(x: W - 16 - 160, y: y, width: 72, height: 24)
        cancelBtn.bezelStyle = .rounded; cancelBtn.keyEquivalent = "\u{1b}"
        doc.addSubview(cancelBtn)
        y += 32

        doc.frame = NSRect(x: 0, y: 0, width: W - 16, height: y + 4)

        let H = min(y + 40, 720.0)
        let win = NSWindow(contentRect: NSRect(x: 200, y: 100, width: W, height: H),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Liuwa Settings"; win.center(); win.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        scroll.hasVerticalScroller = true; scroll.autoresizingMask = [.width, .height]; scroll.drawsBackground = false
        scroll.documentView = doc
        win.contentView = scroll
        self.window = win

        let h = SettingsHandler(
            settingsWindow: self,
            trSl: trSl, wdSl: wdSl, fsSl: fsSl, trV: trV, wdV: wdV, fsV: fsV,
            providerP: providerP, keyF: keyF, modF: modF, endF: endF,
            langCB: langCB, transLocP: transLocP, transLocales: locales,
            txtChk: txtChk, imgChk: imgChk, ssP: ssP,
            attachChk: attachChk,
            pLF: pLF, pPF: pPF, docF: docField, brBtn: brBtn,
            hkFields: hkFields,
            saveBtn: saveBtn, cancelBtn: cancelBtn,
            onLivePreview: { [weak self] in self?.onLivePreview?() }
        )
        self.handler = h
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Snapshot

private struct SettingsSnapshot {
    let transparency: CGFloat; let width: CGFloat; let fontSize: CGFloat
    let llmProvider: String; let remoteAPIKey, remoteModel, remoteEndpoint, responseLanguage: String
    let transcriptionLocale: String
    let sendScreenText, sendScreenshot: Bool; let screenshotMode: String
    let docsDirectory: String; let attachDocToContext: Bool
    let presets: [(String, String)]; let hotkeyBindings: [String: String]

    init(_ s: AppSettings) {
        transparency = s.transparency; width = s.width; fontSize = s.fontSize
        llmProvider = s.llmProvider; remoteAPIKey = s.remoteAPIKey
        remoteModel = s.remoteModel; remoteEndpoint = s.remoteEndpoint
        responseLanguage = s.responseLanguage; transcriptionLocale = s.transcriptionLocale
        sendScreenText = s.sendScreenText
        sendScreenshot = s.sendScreenshot; screenshotMode = s.screenshotMode
        docsDirectory = s.docsDirectory; attachDocToContext = s.attachDocToContext
        presets = s.presets; hotkeyBindings = s.hotkeyBindings
    }

    func restore() {
        let s = AppSettings.shared
        s.transparency = transparency; s.width = width; s.fontSize = fontSize
        s.llmProvider = llmProvider; s.remoteAPIKey = remoteAPIKey
        s.remoteModel = remoteModel; s.remoteEndpoint = remoteEndpoint
        s.responseLanguage = responseLanguage; s.transcriptionLocale = transcriptionLocale
        s.sendScreenText = sendScreenText
        s.sendScreenshot = sendScreenshot; s.screenshotMode = screenshotMode
        s.docsDirectory = docsDirectory; s.attachDocToContext = attachDocToContext
        s.presets = presets; s.hotkeyBindings = hotkeyBindings
        s.save()
    }
}

private final class FlippedView: NSView { override var isFlipped: Bool { true } }

extension SettingsWindow {
    /// Common transcription locales for macOS SpeechTranscriber
    static func transcriptionLocales() -> [(id: String, name: String)] {
        let ids = [
            "en-US", "en-GB", "en-AU", "en-IN",
            "zh-Hans", "zh-Hant",
            "ja-JP", "ko-KR",
            "es-ES", "es-MX",
            "fr-FR", "fr-CA",
            "de-DE", "it-IT", "pt-BR", "pt-PT",
            "ru-RU", "ar-SA", "hi-IN",
            "nl-NL", "sv-SE", "da-DK", "nb-NO", "fi-FI",
            "pl-PL", "tr-TR", "uk-UA", "th-TH", "vi-VN",
            "id-ID", "ms-MY", "ro-RO", "cs-CZ", "hu-HU",
            "el-GR", "he-IL", "ca-ES", "hr-HR", "sk-SK",
        ]
        var result: [(String, String)] = []
        for id in ids {
            let name = Locale.current.localizedString(forIdentifier: id) ?? id
            result.append((id, name))
        }
        return result
    }
}

// MARK: - Handler

@MainActor
private final class SettingsHandler: NSObject, NSTextFieldDelegate {
    weak var settingsWindow: SettingsWindow?
    let trSl, wdSl, fsSl: NSSlider; let trV, wdV, fsV: NSTextField
    let providerP: NSPopUpButton
    let keyF, modF, endF: NSTextField?
    let langCB: NSComboBox; let transLocP: NSPopUpButton; let transLocales: [(id: String, name: String)]
    let txtChk, imgChk: NSButton; let ssP: NSPopUpButton
    let attachChk: NSButton
    let pLF, pPF: [NSTextField]; let docF: NSTextField; let brBtn: NSButton
    let hkFields: [(String, NSTextField)]
    let saveBtn, cancelBtn: NSButton
    let onLivePreview: () -> Void

    init(settingsWindow: SettingsWindow,
         trSl: NSSlider, wdSl: NSSlider, fsSl: NSSlider,
         trV: NSTextField, wdV: NSTextField, fsV: NSTextField,
         providerP: NSPopUpButton, keyF: NSTextField?, modF: NSTextField?, endF: NSTextField?,
         langCB: NSComboBox, transLocP: NSPopUpButton, transLocales: [(id: String, name: String)],
         txtChk: NSButton, imgChk: NSButton, ssP: NSPopUpButton,
         attachChk: NSButton,
         pLF: [NSTextField], pPF: [NSTextField], docF: NSTextField, brBtn: NSButton,
         hkFields: [(String, NSTextField)],
         saveBtn: NSButton, cancelBtn: NSButton,
         onLivePreview: @escaping () -> Void) {
        self.settingsWindow = settingsWindow
        self.trSl = trSl; self.wdSl = wdSl; self.fsSl = fsSl
        self.trV = trV; self.wdV = wdV; self.fsV = fsV
        self.providerP = providerP; self.keyF = keyF; self.modF = modF; self.endF = endF
        self.langCB = langCB; self.transLocP = transLocP; self.transLocales = transLocales
        self.txtChk = txtChk; self.imgChk = imgChk; self.ssP = ssP
        self.attachChk = attachChk
        self.pLF = pLF; self.pPF = pPF; self.docF = docF; self.brBtn = brBtn
        self.hkFields = hkFields
        self.saveBtn = saveBtn; self.cancelBtn = cancelBtn
        self.onLivePreview = onLivePreview
        super.init()

        for sl in [trSl, wdSl, fsSl] { sl.target = self; sl.action = #selector(sliderMoved(_:)); sl.isContinuous = true }
        providerP.target = self; providerP.action = #selector(providerChanged)
        brBtn.target = self; brBtn.action = #selector(browse)
        saveBtn.target = self; saveBtn.action = #selector(save)
        cancelBtn.target = self; cancelBtn.action = #selector(doCancel)
    }

    @objc func sliderMoved(_ sender: NSSlider) {
        let s = AppSettings.shared
        if sender === trSl {
            trV.stringValue = String(format: "%.0f%%", sender.doubleValue * 100)
            s.transparency = CGFloat(sender.doubleValue)
        } else if sender === wdSl {
            wdV.stringValue = String(format: "%.0f", sender.doubleValue)
            s.width = CGFloat(sender.doubleValue)
        } else if sender === fsSl {
            fsV.stringValue = String(format: "%.0f", sender.doubleValue)
            s.fontSize = CGFloat(sender.doubleValue)
        }
        onLivePreview()
    }

    @objc func providerChanged() {
        let s = AppSettings.shared
        let idx = providerP.indexOfSelectedItem
        let newProvider = idx >= 0 && idx < AppSettings.llmProviders.count ? AppSettings.llmProviders[idx] : "local"
        if newProvider != s.llmProvider {
            s.llmProvider = newProvider
            // Clear provider-specific fields when switching
            s.remoteAPIKey = ""
            s.remoteModel = ""
            s.remoteEndpoint = ""
        }
        settingsWindow?.rebuild()
    }

    @objc func save() {
        collectToSettings()
        AppSettings.shared.save()
        settingsWindow?.commitAndClose()
    }

    @objc func doCancel() {
        settingsWindow?.revertAndClose()
    }

    private func collectToSettings() {
        let s = AppSettings.shared
        s.transparency = CGFloat(trSl.doubleValue)
        s.width = CGFloat(wdSl.doubleValue)
        s.fontSize = CGFloat(fsSl.doubleValue)
        let idx = providerP.indexOfSelectedItem
        s.llmProvider = idx >= 0 && idx < AppSettings.llmProviders.count ? AppSettings.llmProviders[idx] : "local"
        if let k = keyF { s.remoteAPIKey = k.stringValue }
        if let m = modF { s.remoteModel = m.stringValue }
        if let e = endF { s.remoteEndpoint = e.stringValue }
        s.responseLanguage = langCB.stringValue.isEmpty ? "English" : langCB.stringValue
        let tIdx = transLocP.indexOfSelectedItem
        if tIdx >= 0 && tIdx < transLocales.count {
            s.transcriptionLocale = transLocales[tIdx].id
        }
        s.sendScreenText = txtChk.state == .on
        s.sendScreenshot = imgChk.state == .on
        let ssModes = ["auto", "ocr", "image"]
        let ssIdx = ssP.indexOfSelectedItem
        s.screenshotMode = ssIdx >= 0 && ssIdx < ssModes.count ? ssModes[ssIdx] : "auto"
        s.docsDirectory = docF.stringValue
        s.attachDocToContext = attachChk.state == .on
        var presets: [(String,String)] = []
        for i in 0..<4 {
            let l = pLF[i].stringValue; let p = pPF[i].stringValue
            presets.append((l.isEmpty ? "Preset \(i+1)" : l, p))
        }
        s.presets = presets

        for (action, field) in hkFields {
            let val = field.stringValue.trimmingCharacters(in: .whitespaces).uppercased()
            if !val.isEmpty {
                s.hotkeyBindings[action] = val
            }
        }
    }

    @objc func browse() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: docF.stringValue)
        if panel.runModal() == .OK, let url = panel.url { docField.stringValue = url.path }
    }

    private var docField: NSTextField { docF }
}
