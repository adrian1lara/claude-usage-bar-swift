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
    private var isClosing = false
    private let gap: CGFloat = 6
    private let fadeInDuration: TimeInterval = 0.16   // open alpha — faster than the spring tail
    private let closeDuration: TimeInterval = 0.16    // close fade + scale-down
    private let openScale: CGFloat = 0.90             // spring pop start
    private let closeScale: CGFloat = 0.96
    // Medium spring: damping ratio ~0.68 → satisfying pop, not toylike.
    private let springStiffness: CGFloat = 260
    private let springDamping: CGFloat = 22

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

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
        // Layer-HOSTING (explicit CALayer before wantsLayer): AppKit then leaves the
        // layer geometry alone, so our custom anchorPoint survives layout and the
        // scale animation grows from top-center, under the status icon.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let hostLayer = CALayer()
        hostLayer.frame = NSRect(origin: .zero, size: size)
        hostLayer.anchorPoint = CGPoint(x: 0.5, y: 1)   // top-center
        hostLayer.position = CGPoint(x: size.width / 2, y: size.height)
        hostLayer.backgroundColor = NSColor.clear.cgColor
        container.layer = hostLayer
        container.wantsLayer = true
        container.addSubview(hosting)
        panel.contentView = container
        return panel
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if panel != nil {
            if !isClosing { hidePanel() }   // ignore clicks mid-close
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

        isClosing = false
        statusItem.button?.highlight(true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        if reduceMotion {
            panel.alphaValue = 1
        } else {
            // Fade in faster than the spring settles, so the pop happens fully opaque.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = fadeInDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
            if let layer = panel.contentView?.layer {
                layer.transform = CATransform3DIdentity   // model = final state
                let spring = CASpringAnimation(keyPath: "transform.scale")
                spring.fromValue = openScale
                spring.toValue = 1.0
                spring.mass = 1
                spring.stiffness = springStiffness
                spring.damping = springDamping
                spring.initialVelocity = 0
                spring.duration = spring.settlingDuration
                layer.add(spring, forKey: "popScale")
            }
        }

        installOutsideMonitor()
    }

    private func hidePanel() {
        guard let panel, !isClosing else { return }
        isClosing = true
        removeOutsideMonitor()

        let finish: () -> Void = { [weak self] in
            panel.orderOut(nil)
            MainActor.assumeIsolated {
                self?.statusItem.button?.highlight(false)
                self?.panel = nil
                self?.isClosing = false
            }
        }

        if reduceMotion {
            panel.alphaValue = 0
            finish()
            return
        }

        let layer = panel.contentView?.layer
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = closeDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            if let layer {
                layer.transform = CATransform3DMakeScale(closeScale, closeScale, 1)
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = 1.0
                scale.toValue = closeScale
                scale.duration = closeDuration
                scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(scale, forKey: "popScale")
            }
        }, completionHandler: finish)   // completion runs on main thread
    }

    // MARK: - Outside-click dismissal

    private func installOutsideMonitor() {
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isClosing else { return }
                self.hidePanel()   // global monitor fires on main thread
            }
        }
    }

    private func removeOutsideMonitor() {
        if let m = outsideMonitor { NSEvent.removeMonitor(m) }
        outsideMonitor = nil
    }
}
