import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
    var overlay: OverlayController!
    var hotkeys: HotkeyManager!
    var transcription: TranscriptionManager!
    var screenCapture: ScreenCaptureManager!
    var llm: LLMManager!
    var systemAudio: SystemAudioManager!
    var docs: DocumentManager!
    var settings: SettingsWindow!

    private var setupWindow: NSWindow?
    private var permTimer: Timer?
    private var axLabel: NSTextField?
    private var micLabel: NSTextField?
    private var scrLabel: NSTextField?
    private var continueBtn: NSButton?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupEditMenu()
        Task { await AppSettings.fetchSupportedLocales() }

        if allPermissionsGranted() {
            launchApp()
        } else {
            showPermissionWindow()
        }
    }

    // MARK: - Permissions

    private func allPermissionsGranted() -> Bool {
        AXIsProcessTrusted()
        && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        && CGPreflightScreenCaptureAccess()
    }

    @MainActor private func showPermissionWindow() {
        NSApp.setActivationPolicy(.regular)

        let w: CGFloat = 460, h: CGFloat = 310
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = NSRect(x: (screen.frame.width - w) / 2, y: (screen.frame.height - h) / 2, width: w, height: h)
        let win = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Liuwa — Setup"; win.level = .floating; win.isReleasedWhenClosed = false

        let root = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        let title = NSTextField(labelWithString: "Liuwa needs permissions to work properly")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.frame = NSRect(x: 20, y: h - 40, width: w - 40, height: 24)
        root.addSubview(title)

        let desc = NSTextField(wrappingLabelWithString:
            "Liuwa uses an invisible overlay with global hotkeys. " +
            "Without these permissions, hotkeys and capture won't work.\n\n" +
            "Grant all permissions in System Settings, then click Continue.")
        desc.font = .systemFont(ofSize: 12)
        desc.frame = NSRect(x: 20, y: h - 120, width: w - 40, height: 72)
        root.addSubview(desc)

        var y = h - 155
        axLabel  = makePermRow(parent: root, y: y, label: "Accessibility (required)", status: AXIsProcessTrusted()); y -= 28
        micLabel = makePermRow(parent: root, y: y, label: "Microphone (for transcription)", status: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized); y -= 28
        scrLabel = makePermRow(parent: root, y: y, label: "Screen Recording (for screen capture)", status: CGPreflightScreenCaptureAccess()); y -= 40

        let axBtn = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(openAccessibilitySettings))
        axBtn.bezelStyle = .rounded; axBtn.frame = NSRect(x: 20, y: y, width: 220, height: 28); root.addSubview(axBtn)

        let micBtn = NSButton(title: "Open Microphone Settings…", target: self, action: #selector(openMicSettings))
        micBtn.bezelStyle = .rounded; micBtn.frame = NSRect(x: 250, y: y, width: 190, height: 28); root.addSubview(micBtn)
        y -= 36

        let scrBtn = NSButton(title: "Open Screen Recording Settings…", target: self, action: #selector(openScreenSettings))
        scrBtn.bezelStyle = .rounded; scrBtn.frame = NSRect(x: 20, y: y, width: 250, height: 28); root.addSubview(scrBtn)

        let btn = NSButton(title: "Continue", target: self, action: #selector(permContinue))
        btn.bezelStyle = .rounded; btn.font = .systemFont(ofSize: 14, weight: .semibold)
        btn.frame = NSRect(x: w - 130, y: 16, width: 110, height: 32)
        btn.isEnabled = allPermissionsGranted(); btn.keyEquivalent = "\r"
        root.addSubview(btn); continueBtn = btn

        win.contentView = root; win.delegate = self
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        setupWindow = win

        permTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updatePermStatus() }
        }
    }

    @MainActor private func makePermRow(parent: NSView, y: CGFloat, label: String, status: Bool) -> NSTextField {
        let lbl = NSTextField(labelWithString: "\(status ? "✅" : "❌")  \(label)")
        lbl.font = .systemFont(ofSize: 13)
        lbl.frame = NSRect(x: 24, y: y, width: parent.frame.width - 48, height: 20)
        parent.addSubview(lbl); return lbl
    }

    @MainActor private func updatePermStatus() {
        let ax = AXIsProcessTrusted(), mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, scr = CGPreflightScreenCaptureAccess()
        axLabel?.stringValue  = "\(ax  ? "✅" : "❌")  Accessibility"
        micLabel?.stringValue = "\(mic ? "✅" : "❌")  Microphone"
        scrLabel?.stringValue = "\(scr ? "✅" : "❌")  Screen Recording"
        continueBtn?.isEnabled = ax && mic && scr
    }

    @objc private func openAccessibilitySettings() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    @objc private func openMicSettings() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in self.updatePermStatus() } }
    }
    @objc private func openScreenSettings() { CGRequestScreenCaptureAccess() }

    func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? NSWindow, win === setupWindow {
            permTimer?.invalidate(); permTimer = nil; setupWindow = nil
            NSApp.terminate(nil)
        }
    }

    @objc @MainActor private func permContinue() {
        guard allPermissionsGranted() else { return }
        permTimer?.invalidate(); permTimer = nil
        setupWindow?.close(); setupWindow = nil
        NSApp.setActivationPolicy(.accessory)
        launchApp()
    }

    // MARK: - Launch

    @MainActor private func launchApp() {
        overlay = OverlayController()
        transcription = TranscriptionManager(overlay: overlay)
        screenCapture = ScreenCaptureManager(overlay: overlay)
        llm = LLMManager(overlay: overlay)
        llm.screenCapture = screenCapture
        systemAudio = SystemAudioManager(overlay: overlay)
        docs = DocumentManager(overlay: overlay)
        llm.docs = docs
        settings = SettingsWindow()

        hotkeys = HotkeyManager()
        hotkeys.onAction = { [weak self] action in self?.handle(action) }
        settings.onChanged = { [weak self] in
            self?.overlay.applySettings(); self?.hotkeys.reloadBindings()
            self?.llm.reloadConfig(); self?.docs.reload()
        }
        settings.onLivePreview = { [weak self] in self?.overlay.livePreview() }

        if hotkeys.install() { print("Hotkeys OK") }
        else { print("CGEventTap failed — check Accessibility permission") }

        if overlay.docsVisible { docs.showDocuments() }
    }

    @MainActor private func setupEditMenu() {
        let mainMenu = NSMenu()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu; mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    @MainActor private func handle(_ action: HotkeyAction) {
        let s = AppSettings.shared
        switch action {
        case .toggleOverlay:       overlay.toggleVisibility()
        case .toggleGhost:         overlay.toggleGhostMode()
        case .toggleClickThrough:  overlay.toggleClickThrough()
        case .toggleTranscription: transcription.toggle()
        case .toggleSystemAudio:   systemAudio.toggle()
        case .clearTranscription:  transcription.clearTranscript(); systemAudio.clearTranscript()
        case .showDocs:
            overlay.toggleDocs()
            if overlay.docsVisible { docs.showDocuments() }
        case .scrollDocUp:         if overlay.docsVisible { overlay.scrollDocUp() }
        case .scrollDocDown:       if overlay.docsVisible { overlay.scrollDocDown() }
        case .docPrev:             if overlay.docsVisible { docs.previousDocument() }
        case .docNext:             if overlay.docsVisible { docs.nextDocument() }
        case .toggleAttachDoc:
            guard overlay.docsVisible else { break }
            s.attachDocToContext.toggle(); s.save(); overlay.refreshStatus()
        case .openSettings:        settings.toggle()
        case .cycleScreenText:     s.sendScreenText.toggle(); s.save(); overlay.refreshStatus()
        case .cycleScreenshot:     s.sendScreenshot.toggle(); s.save(); overlay.refreshStatus()
        case .clearAI:             llm.clearConversation(); overlay.setText("", for: .aiResponse)
        case .scrollAIUp:          overlay.scrollAIUp()
        case .scrollAIDown:        overlay.scrollAIDown()
        case .preset1:             llm.sendPresetQuery(s.presets[safe: 0]?.prompt ?? "")
        case .preset2:             llm.sendPresetQuery(s.presets[safe: 1]?.prompt ?? "")
        case .preset3:             llm.sendPresetQuery(s.presets[safe: 2]?.prompt ?? "")
        case .preset4:             llm.sendPresetQuery(s.presets[safe: 3]?.prompt ?? "")
        case .quit:
            transcription.stop(); systemAudio.stop()
            NSApplication.shared.terminate(nil)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
