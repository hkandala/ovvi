import SwiftUI

extension View {
    /// Liquid Glass: the system glass alone, as the system's menus draw it (measured beside one), or over a material,
    /// which keeps the page's text from competing with a small panel's own. Classic: solid, as a tip.
    func floatingGlass(in shape: some InsettableShape, material: Material? = .ultraThinMaterial) -> some View {
        modifier(FloatingGlass(shape: shape, material: material))
    }
}

private struct FloatingGlass<Panel: InsettableShape>: ViewModifier {
    let shape: Panel
    let material: Material?
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        if look.style == .classic {
            let tip = look.tip
            content.background {
                shape.fill(tip.fill).overlay(shape.strokeBorder(tip.rim)).shadow(color: tip.shadow, radius: 18, y: 8)
            }
        } else if let material {
            content.glassEffect(.regular, in: shape).background(material, in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}
