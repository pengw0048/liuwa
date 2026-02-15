import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    var overlay: OverlayController!
    var hotkeys: HotkeyManager!
    var transcription: TranscriptionManager!
    var screenCapture: ScreenCaptureManager!
    var llm: LLMManager!
    var systemAudio: SystemAudioManager!
    var docs: DocumentManager!
    var settings: SettingsWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupEditMenu()

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
            self?.overlay.applySettings()
            self?.hotkeys.reloadBindings()
            self?.llm.reloadConfig()
            self?.docs.reload()
        }
        settings.onLivePreview = { [weak self] in self?.overlay.livePreview() }

        if hotkeys.install() { print("Hotkeys OK") }
        else { print("CGEventTap failed - enable Accessibility") }

        print("Liuwa started.")
    }

    /// Standard Edit menu so Cmd+C/V/X/A work in text fields
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
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @MainActor private func handle(_ action: HotkeyAction) {
        let s = AppSettings.shared
        switch action {
        case .toggleOverlay: overlay.toggleVisibility()
        case .toggleGhost: overlay.toggleGhostMode()
        case .toggleClickThrough: overlay.toggleClickThrough()
        case .toggleTranscription: transcription.toggle()
        case .toggleSystemAudio: systemAudio.toggle()
        case .clearTranscription:
            transcription.clearTranscript(); systemAudio.clearTranscript()
        case .showDocs: docs.showDocuments()
        case .docPrev: docs.previousDocument()
        case .docNext: docs.nextDocument()
        case .toggleAttachDoc:
            s.attachDocToContext.toggle(); s.save(); overlay.refreshStatus()
        case .openSettings: settings.toggle()
        case .cycleScreenText:
            s.sendScreenText.toggle(); s.save(); overlay.refreshStatus()
        case .cycleScreenshot:
            s.sendScreenshot.toggle(); s.save(); overlay.refreshStatus()
        case .clearAI: llm.clearConversation(); overlay.setText("", for: .aiResponse)
        case .scrollAIUp: overlay.scrollAIUp()
        case .scrollAIDown: overlay.scrollAIDown()
        case .preset1: llm.sendPresetQuery(s.presets[safe: 0]?.prompt ?? "")
        case .preset2: llm.sendPresetQuery(s.presets[safe: 1]?.prompt ?? "")
        case .preset3: llm.sendPresetQuery(s.presets[safe: 2]?.prompt ?? "")
        case .preset4: llm.sendPresetQuery(s.presets[safe: 3]?.prompt ?? "")
        case .quit:
            transcription.stop(); systemAudio.stop()
            print("Liuwa exiting."); NSApplication.shared.terminate(nil)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
