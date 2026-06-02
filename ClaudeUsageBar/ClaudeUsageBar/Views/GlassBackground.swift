import SwiftUI

/// Liquid Glass rounded-rect background for the floating panel content.
/// The host panel is transparent, so this provides the visible surface.
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}
