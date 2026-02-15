import AppKit
import Foundation

// Disable stdout buffering so print() output shows immediately
setbuf(stdout, nil)
setbuf(stderr, nil)

// Create the NSApplication instance
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon, no menu bar

// Create and set the app delegate
let delegate = AppDelegate()
app.delegate = delegate

// Run the app
app.run()
