import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let session = ClaudeSession()
    private let launch = LaunchAtLogin()
    private let notifier = Notifier()
    private lazy var poller = UsagePoller(session: session, settings: settings)
    private var statusController: StatusItemController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier.requestAuthorization()
        buildMainMenu()

        let controller = StatusItemController(
            poller: poller,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onSignIn: { [weak self] in self?.session.openLogin() })
        statusController = controller

        // Refresh as soon as the login window closes so signed-in state shows immediately.
        session.onLoginFinished = { [weak self] in self?.poller.refreshNow() }

        poller.onUpdate = { [weak self] state in
            guard let self else { return }
            controller.render(state: state)
            self.notifier.check(state: state, settings: self.settings)
        }
        poller.start()

        // Sleep/wake: rebuild scraper + immediate refresh.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func handleWake() {
        session.resetScraper()
        poller.restart()
        poller.refreshNow()
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettingsAction),
                                      keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Claude Usage Bar",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))

        // Edit menu so standard ⌘C/⌘V/⌘X/⌘A work in the login web view & text fields.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsAction() { openSettings() }

    private func openSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = SettingsView(settings: settings, session: session, launch: launch,
            onIntervalChange: { [weak self] in self?.poller.restart() },
            onAuthChange: { [weak self] in self?.poller.refreshNow() },
            onTestNotification: { [weak self] in self?.notifier.postTest() })
        let win = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 448),
                           styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        win.title = "Settings"
        win.titlebarAppearsTransparent = true
        win.contentView = NSHostingView(rootView: view)
        win.setContentSize(NSSize(width: 360, height: 448))
        win.isMovableByWindowBackground = true
        win.center()
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
