import AppKit

enum UsageTier { case normal, warn, critical }

enum UsageFormatting {
    static func menuBarLabel(for percent: Int?) -> String {
        guard let p = percent else { return "—" }
        return "\(p)%"
    }

    static func tier(for percent: Int) -> UsageTier {
        switch percent {
        case ..<50: return .normal
        case 50..<90: return .warn
        default: return .critical
        }
    }

    static func color(for percent: Int?) -> NSColor {
        guard let p = percent else { return .secondaryLabelColor }
        switch tier(for: p) {
        case .normal: return .systemGreen
        case .warn: return .systemOrange
        case .critical: return .systemRed
        }
    }

    static func attributedTitle(for percent: Int?) -> NSAttributedString {
        let label = menuBarLabel(for: percent)
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold).rounded()
        return NSAttributedString(string: label, attributes: [
            .font: font,
            .foregroundColor: color(for: percent),
        ])
    }
}

private extension NSFont {
    func rounded() -> NSFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}
