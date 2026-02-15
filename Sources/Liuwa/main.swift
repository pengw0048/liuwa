import AppKit
import Foundation

// Disable stdout buffering so print() output shows immediately
setbuf(stdout, nil)
setbuf(stderr, nil)

// Prevent running two instances
let runningApps = NSWorkspace.shared.runningApplications.filter {
    $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
}
if let bundleID = Bundle.main.bundleIdentifier, !runningApps.isEmpty {
    print("Liuwa is already running (pid \(runningApps[0].processIdentifier), bundle \(bundleID)). Exiting.")
    exit(0)
}

// Create the NSApplication instance
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon, no menu bar

// Create and set the app delegate
let delegate = AppDelegate()
app.delegate = delegate

// Run the app
app.run()
