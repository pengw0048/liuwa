import AppKit

setbuf(stdout, nil)
setbuf(stderr, nil)

// Prevent duplicate instances
if let bid = Bundle.main.bundleIdentifier {
    let dupes = NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == bid && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }
    if !dupes.isEmpty { print("Liuwa already running."); exit(0) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
