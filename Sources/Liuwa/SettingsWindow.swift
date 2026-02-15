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
        let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: W - 16, height: 1200))
        var y: CGFloat = 8
        let lx: CGFloat = 12, fx: CGFloat = 140, fw: CGFloat = 290

        func sec(_ t: String) {
            if y > 12 { y += 4 }  // spacing before section
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
        let seg = NSSegmentedControl(labels: ["Local (Apple AI)", "Remote API"], trackingMode: .selectOne, target: nil, action: nil)
        seg.frame = NSRect(x: fx, y: y, width: 220, height: 22)
        seg.selectedSegment = s.useLocalModel ? 0 : 1
        doc.addSubview(seg); y += 26

        var keyF: NSSecureTextField?
        var modF: NSTextField?
        var endF: NSTextField?
        if !s.useLocalModel {
            lbl("API Key:")
            let k = NSSecureTextField(string: s.remoteAPIKey); k.frame = NSRect(x: fx, y: y, width: fw, height: 18); k.placeholderString = "sk-..."; doc.addSubview(k); keyF = k; y += 20
            lbl("Model:")
            let m = NSTextField(string: s.remoteModel); m.frame = NSRect(x: fx, y: y, width: fw, height: 18); m.placeholderString = "gpt-4o-mini"; doc.addSubview(m); modF = m; y += 20
            lbl("Endpoint:")
            let e = NSTextField(string: s.remoteEndpoint); e.frame = NSRect(x: fx, y: y, width: fw, height: 18); e.placeholderString = "https://api.openai.com/v1/chat/completions"; doc.addSubview(e); endF = e; y += 22
        }

        lbl("Language:")
        let langP = NSPopUpButton(frame: NSRect(x: fx, y: y-2, width: 110, height: 20))
        for l in ["English","Chinese","Japanese","Korean","Spanish","French","German"] { langP.addItem(withTitle: l) }
        if let i = ["English","Chinese","Japanese","Korean","Spanish","French","German"].firstIndex(of: s.responseLanguage) { langP.selectItem(at: i) }
        langP.font = .systemFont(ofSize: 11); doc.addSubview(langP); y += 20

        // ── Screen Capture ──
        sec("Screen Capture")
        let txtChk = NSButton(checkboxWithTitle: "📝 Send text (Accessibility)", target: nil, action: nil)
        txtChk.state = s.sendScreenText ? .on : .off; txtChk.frame = NSRect(x: fx, y: y, width: 300, height: 16); doc.addSubview(txtChk); y += 19
        let imgChk = NSButton(checkboxWithTitle: "📷 Send screenshot (OCR)", target: nil, action: nil)
        imgChk.state = s.sendScreenshot ? .on : .off; imgChk.frame = NSRect(x: fx, y: y, width: 300, height: 16); doc.addSubview(imgChk); y += 20

        // ── Presets ──
        sec("AI Presets (⌘⌥ 1-4)")
        var pLF = [NSTextField](), pPF = [NSTextField]()
        for i in 0..<4 {
            let p = s.presets[safe: i]
            lbl("⌘⌥\(i+1):")
            let lf = NSTextField(string: p?.label ?? ""); lf.frame = NSRect(x: fx, y: y, width: 66, height: 18); lf.placeholderString = "Label"; lf.font = .systemFont(ofSize: 11); doc.addSubview(lf); pLF.append(lf)
            let pf = NSTextField(string: p?.prompt ?? ""); pf.frame = NSRect(x: fx+72, y: y, width: fw-72, height: 18); pf.placeholderString = "Prompt"; pf.font = .systemFont(ofSize: 10); doc.addSubview(pf); pPF.append(pf); y += 21
        }

        // ── Documents ──
        sec("Documents")
        lbl("Directory:")
        let docField = NSTextField(string: s.docsDirectory); docField.frame = NSRect(x: fx, y: y, width: fw-54, height: 18); docField.font = .systemFont(ofSize: 10); doc.addSubview(docField)
        let brBtn = NSButton(title: "Browse…", target: nil, action: nil); brBtn.frame = NSRect(x: fx+fw-50, y: y-1, width: 54, height: 20); brBtn.font = .systemFont(ofSize: 10); doc.addSubview(brBtn); y += 22

        // ── Hotkeys ──
        sec("Hotkeys (all ⌘⌥ + key)")
        // Define actions in display order with descriptions
        let hotkeyDefs: [(action: String, label: String)] = [
            ("toggleOverlay", "👁‍🗨 Show/Hide"),
            ("toggleGhost", "👻 Ghost"),
            ("toggleClickThrough", "🖱 Click-through"),
            ("openSettings", "⚙ Settings"),
            ("toggleTranscription", "🎤 Mic"),
            ("toggleSystemAudio", "🔊 System Audio"),
            ("cycleScreenText", "📝 Screen Text"),
            ("cycleScreenshot", "📷 Screenshot"),
            ("preset1", "1️⃣ Preset 1"),
            ("preset2", "2️⃣ Preset 2"),
            ("preset3", "3️⃣ Preset 3"),
            ("preset4", "4️⃣ Preset 4"),
            ("clearAI", "🧹 Clear AI"),
            ("showDocs", "📂 Documents"),
            ("quit", "❌ Quit"),
        ]

        // Two-column grid
        let colW: CGFloat = (W - 40) / 2
        var hkFields: [(String, NSTextField)] = []  // (action, field)
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
        if col != 0 { y += 20 }  // finish last row

        // Arrow keys (read-only)
        let arrowL = NSTextField(labelWithString: "↑↓ Scroll AI (fixed)")
        arrowL.font = .systemFont(ofSize: 10); arrowL.textColor = .secondaryLabelColor
        arrowL.frame = NSRect(x: lx, y: y, width: 200, height: 14); doc.addSubview(arrowL); y += 18

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

        let H = min(y + 40, 680.0)
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
            seg: seg, keyF: keyF, modF: modF, endF: endF,
            langP: langP, txtChk: txtChk, imgChk: imgChk,
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
    let useLocalModel: Bool; let remoteAPIKey, remoteModel, remoteEndpoint, responseLanguage: String
    let sendScreenText, sendScreenshot: Bool; let docsDirectory: String
    let presets: [(String, String)]; let hotkeyBindings: [String: String]

    init(_ s: AppSettings) {
        transparency = s.transparency; width = s.width; fontSize = s.fontSize
        useLocalModel = s.useLocalModel; remoteAPIKey = s.remoteAPIKey
        remoteModel = s.remoteModel; remoteEndpoint = s.remoteEndpoint
        responseLanguage = s.responseLanguage; sendScreenText = s.sendScreenText
        sendScreenshot = s.sendScreenshot; docsDirectory = s.docsDirectory
        presets = s.presets; hotkeyBindings = s.hotkeyBindings
    }

    func restore() {
        let s = AppSettings.shared
        s.transparency = transparency; s.width = width; s.fontSize = fontSize
        s.useLocalModel = useLocalModel; s.remoteAPIKey = remoteAPIKey
        s.remoteModel = remoteModel; s.remoteEndpoint = remoteEndpoint
        s.responseLanguage = responseLanguage; s.sendScreenText = sendScreenText
        s.sendScreenshot = sendScreenshot; s.docsDirectory = docsDirectory
        s.presets = presets; s.hotkeyBindings = hotkeyBindings
        s.save()
    }
}

private final class FlippedView: NSView { override var isFlipped: Bool { true } }

// MARK: - Handler

@MainActor
private final class SettingsHandler: NSObject, NSTextFieldDelegate {
    weak var settingsWindow: SettingsWindow?
    let trSl, wdSl, fsSl: NSSlider; let trV, wdV, fsV: NSTextField
    let seg: NSSegmentedControl
    let keyF: NSSecureTextField?; let modF, endF: NSTextField?
    let langP: NSPopUpButton; let txtChk, imgChk: NSButton
    let pLF, pPF: [NSTextField]; let docF: NSTextField; let brBtn: NSButton
    let hkFields: [(String, NSTextField)]
    let saveBtn, cancelBtn: NSButton
    let onLivePreview: () -> Void

    init(settingsWindow: SettingsWindow,
         trSl: NSSlider, wdSl: NSSlider, fsSl: NSSlider,
         trV: NSTextField, wdV: NSTextField, fsV: NSTextField,
         seg: NSSegmentedControl, keyF: NSSecureTextField?, modF: NSTextField?, endF: NSTextField?,
         langP: NSPopUpButton, txtChk: NSButton, imgChk: NSButton,
         pLF: [NSTextField], pPF: [NSTextField], docF: NSTextField, brBtn: NSButton,
         hkFields: [(String, NSTextField)],
         saveBtn: NSButton, cancelBtn: NSButton,
         onLivePreview: @escaping () -> Void) {
        self.settingsWindow = settingsWindow
        self.trSl = trSl; self.wdSl = wdSl; self.fsSl = fsSl
        self.trV = trV; self.wdV = wdV; self.fsV = fsV
        self.seg = seg; self.keyF = keyF; self.modF = modF; self.endF = endF
        self.langP = langP; self.txtChk = txtChk; self.imgChk = imgChk
        self.pLF = pLF; self.pPF = pPF; self.docF = docF; self.brBtn = brBtn
        self.hkFields = hkFields
        self.saveBtn = saveBtn; self.cancelBtn = cancelBtn
        self.onLivePreview = onLivePreview
        super.init()

        // All sliders: live preview
        for sl in [trSl, wdSl, fsSl] { sl.target = self; sl.action = #selector(sliderMoved(_:)); sl.isContinuous = true }
        seg.target = self; seg.action = #selector(segChanged)
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

    @objc func segChanged() {
        collectToSettings()
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
        s.useLocalModel = seg.selectedSegment == 0
        if let k = keyF { s.remoteAPIKey = k.stringValue }
        if let m = modF { s.remoteModel = m.stringValue }
        if let e = endF { s.remoteEndpoint = e.stringValue }
        s.responseLanguage = langP.titleOfSelectedItem ?? "English"
        s.sendScreenText = txtChk.state == .on
        s.sendScreenshot = imgChk.state == .on
        s.docsDirectory = docF.stringValue
        var presets: [(String,String)] = []
        for i in 0..<4 {
            let l = pLF[i].stringValue; let p = pPF[i].stringValue
            presets.append((l.isEmpty ? "Preset \(i+1)" : l, p))
        }
        s.presets = presets

        // Collect hotkey bindings
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
        if panel.runModal() == .OK, let url = panel.url { docF.stringValue = url.path }
    }
}
