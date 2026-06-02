import AppKit
import SwiftUI

/// Borderless panel that can become key so SwiftUI buttons/fields work.
private final class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let poller: UsagePoller
    private let onOpenSettings: () -> Void
    private let onSignIn: () -> Void
    private var lastRenderedPercent: Int?
    private var lastSignedOut: Bool?

    private var panel: PopoverPanel?
    private var outsideMonitor: Any?
    private let gap: CGFloat = 6
    private let fadeDuration: TimeInterval = 0.18

    init(poller: UsagePoller, onOpenSettings: @escaping () -> Void, onSignIn: @escaping () -> Void) {
        self.poller = poller
        self.onOpenSettings = onOpenSettings
        self.onSignIn = onSignIn
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.image(percent: nil)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func render(state: UsageState) {
        if state.signedOut {
            guard lastSignedOut != true else { return }
            lastSignedOut = true
            lastRenderedPercent = nil
            statusItem.button?.image = MenuBarIcon.signedOutImage()
            return
        }
        lastSignedOut = false
        let p = state.sessionPercent
        guard p != lastRenderedPercent else { return }   // re-render only on change
        lastRenderedPercent = p
        statusItem.button?.image = MenuBarIcon.image(percent: p)
    }

    // MARK: - Panel lifecycle

    private func makePanel() -> PopoverPanel {
        let openSettings: () -> Void = { [weak self] in
            self?.hidePanel()
            self?.onOpenSettings()
        }
        let signIn: () -> Void = { [weak self] in
            self?.hidePanel()
            self?.onSignIn()
        }
        let hosting = NSHostingView(rootView: PopoverView(poller: poller, onOpenSettings: openSettings, onSignIn: signIn))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        let panel = PopoverPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // glass provides its own; window shadow boxes the square frame
        panel.level = .statusBar
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false

        // Transparent container so nothing square shows behind the rounded glass.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting)
        panel.contentView = container
        return panel
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if panel != nil {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        if panel != nil { hidePanel() }
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Claude Usage Bar",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        button.performClick(nil)   // pops the menu under the status item
        statusItem.menu = nil      // restore left-click toggle behavior
    }

    @objc private func menuOpenSettings() { onOpenSettings() }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let panel = makePanel()
        self.panel = panel

        // Position centered under the status item, small gap, no arrow.
        let buttonInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        let origin = NSPoint(
            x: buttonInScreen.midX - size.width / 2,
            y: buttonInScreen.minY - gap - size.height)
        panel.setFrameOrigin(origin)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installOutsideMonitor()
    }

    private func hidePanel() {
        guard let panel else { return }
        removeOutsideMonitor()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            MainActor.assumeIsolated { self?.panel = nil }   // completion runs on main thread
        })
    }

    // MARK: - Outside-click dismissal

    private func installOutsideMonitor() {
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }   // global monitor fires on main thread
        }
    }

    private func removeOutsideMonitor() {
        if let m = outsideMonitor { NSEvent.removeMonitor(m) }
        outsideMonitor = nil
    }
}
