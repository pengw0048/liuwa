import AppKit
import CoreGraphics
import CoreFoundation

enum HotkeyAction: String, CaseIterable {
    case toggleOverlay
    case toggleGhost
    case toggleClickThrough
    case toggleTranscription
    case toggleSystemAudio
    case clearTranscription
    case showDocs
    case toggleAttachDoc
    case openSettings
    case cycleScreenText
    case cycleScreenshot
    case clearAI
    case scrollAIUp
    case scrollAIDown
    case preset1, preset2, preset3, preset4
    case scrollDocUp, scrollDocDown
    case docPrev, docNext
    case quit
}

final class HotkeyManager: @unchecked Sendable {
    var onAction: (@MainActor (HotkeyAction) -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Current key-code-to-action mapping (built from AppSettings)
    var keyMap: [Int64: HotkeyAction] = [:]

    fileprivate final class Ctx: @unchecked Sendable { weak var mgr: HotkeyManager? }
    fileprivate let ctx = Ctx()

    // Character -> macOS virtual key code
    static let charToKeyCode: [String: Int64] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05,
        "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C,
        "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10, "T": 0x11,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16,
        "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
        "O": 0x1F, "U": 0x20, "I": 0x22, "P": 0x23, "L": 0x25, "J": 0x26,
        "K": 0x28, "N": 0x2D, "M": 0x2E,
        "↑": 0x7E, "↓": 0x7D, "←": 0x7B, "→": 0x7C,
    ]

    init() {
        ctx.mgr = self
        reloadBindings()
    }

    /// Rebuild keyMap from AppSettings.hotkeyBindings
    func reloadBindings() {
        keyMap.removeAll()
        let bindings = AppSettings.shared.hotkeyBindings
        for (actionName, keyChar) in bindings {
            guard let action = HotkeyAction(rawValue: actionName),
                  let code = Self.charToKeyCode[keyChar.uppercased()] else { continue }
            keyMap[code] = action
        }
    }

    func install() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let ctxPtr = Unmanaged.passUnretained(ctx).toOpaque()
        let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                     options: .defaultTap, eventsOfInterest: mask,
                                     callback: hotkeyCallback, userInfo: ctxPtr)
        guard let tap else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap; runLoopSource = source
        return true
    }

    fileprivate func dispatch(_ action: HotkeyAction) {
        Task { @MainActor [weak self] in self?.onAction?(action) }
    }
}

private func hotkeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return Unmanaged.passRetained(event) }
    guard type == .keyDown else { return Unmanaged.passRetained(event) }
    let flags = event.flags; let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    guard flags.contains([.maskCommand, .maskAlternate]),
          flags.isDisjoint(with: [.maskShift, .maskControl]) else { return Unmanaged.passRetained(event) }
    guard let ptr = userInfo else { return Unmanaged.passRetained(event) }
    let mgr = Unmanaged<HotkeyManager.Ctx>.fromOpaque(ptr).takeUnretainedValue().mgr
    guard let action = mgr?.keyMap[keyCode] else { return Unmanaged.passRetained(event) }
    mgr?.dispatch(action)
    return nil
}
