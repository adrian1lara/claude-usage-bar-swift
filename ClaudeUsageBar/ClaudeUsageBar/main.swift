import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // agent app: no Dock icon, menu bar only

// Top-level code is nonisolated; AppDelegate is @MainActor. main runs on the main thread.
let delegate = MainActor.assumeIsolated { AppDelegate() }
MainActor.assumeIsolated { app.delegate = delegate }
app.run()
