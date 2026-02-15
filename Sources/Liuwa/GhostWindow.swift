import AppKit
import Quartz

final class GhostWindow: NSWindow {
    private var baseAlpha: CGFloat = 0.75
    private var isGhostMode: Bool = true

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        configure()
    }

    func setBaseAlpha(_ a: CGFloat) { baseAlpha = a; alphaValue = a }

    /// Toggle invisible-to-capture mode
    func toggleGhostMode() {
        isGhostMode.toggle()
        sharingType = isGhostMode ? .none : .readOnly
    }

    var ghostModeOn: Bool { isGhostMode }

    /// Toggle click-through
    func toggleClickThrough() {
        ignoresMouseEvents.toggle()
    }

    var clickThroughOn: Bool { ignoresMouseEvents }

    private func configure() {
        sharingType = .none
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = true; hidesOnDeactivate = false
        isMovableByWindowBackground = false
    }
}
