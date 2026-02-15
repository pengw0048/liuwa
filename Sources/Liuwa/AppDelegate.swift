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
        overlay = OverlayController()
        transcription = TranscriptionManager(overlay: overlay)
        screenCapture = ScreenCaptureManager(overlay: overlay)
        llm = LLMManager(overlay: overlay, transcription: transcription)
        llm.screenCapture = screenCapture
        systemAudio = SystemAudioManager(overlay: overlay)
        docs = DocumentManager(overlay: overlay)
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

    @MainActor private func handle(_ action: HotkeyAction) {
        let s = AppSettings.shared
        switch action {
        case .toggleOverlay: overlay.toggleVisibility()
        case .toggleGhost: overlay.toggleGhostMode()
        case .toggleClickThrough: overlay.toggleClickThrough()
        case .toggleTranscription: transcription.toggle()
        case .toggleSystemAudio: systemAudio.toggle()
        case .showDocs: docs.showDocuments()
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
