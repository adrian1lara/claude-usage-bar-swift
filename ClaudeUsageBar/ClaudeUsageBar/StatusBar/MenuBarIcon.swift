import AppKit

/// Renders the menu-bar glyph: percent text with a small progress bar beneath,
/// as a monochrome template image so macOS adapts it to light/dark menu bars.
enum MenuBarIcon {
    /// Shown when no valid Claude session — prompts the user to sign in.
    static func signedOutImage() -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let img =
            NSImage(
                systemSymbolName: "person.crop.circle.badge.exclamationmark",
                accessibilityDescription: "Not signed in")?
            .withSymbolConfiguration(cfg) ?? NSImage()
        img.isTemplate = true
        return img
    }

    static func image(percent: Int?) -> NSImage {
        let label = percent.map { "\($0)%" } ?? "—"
        let base = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let font =
            base.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: 9) } ?? base
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = (label as NSString).size(withAttributes: attrs)

        let width = max(22, ceil(textSize.width) + 2)
        let height: CGFloat = 22
        let barHeight: CGFloat = 4

        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()

        let textRect = NSRect(
            x: (width - textSize.width) / 2,
            y: height - textSize.height - 1,
            width: textSize.width, height: textSize.height)
        (label as NSString).draw(in: textRect, withAttributes: attrs)

        if let p = percent {
            let barY: CGFloat = 3
            let barWidth = width - 4
            let track = NSRect(x: 2, y: barY, width: barWidth, height: barHeight)
            NSColor.black.withAlphaComponent(0.3).setFill()
            NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

            let fillWidth = barWidth * CGFloat(min(100, max(0, p))) / 100
            let fill = NSRect(x: 2, y: barY, width: fillWidth, height: barHeight)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: fill, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        }

        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
