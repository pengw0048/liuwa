import AppKit

final class GhostWindow: NSWindow {
    private var baseAlpha: CGFloat = 0.75
    private var isGhostMode = true

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        sharingType = .none
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = true; hidesOnDeactivate = false
        isMovableByWindowBackground = false
    }

    func setBaseAlpha(_ a: CGFloat) { baseAlpha = a; alphaValue = a }

    var ghostModeOn: Bool { isGhostMode }
    func toggleGhostMode() {
        isGhostMode.toggle()
        sharingType = isGhostMode ? .none : .readOnly
    }

    var clickThroughOn: Bool { ignoresMouseEvents }
    func toggleClickThrough() { ignoresMouseEvents.toggle() }
}
