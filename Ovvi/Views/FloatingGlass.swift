import SwiftUI

extension View {
    /// Liquid Glass: the system glass over a material, as Liquid Glass alone lets the text behind compete with a small
    /// panel's own; the ultra-thin one still shows the page's layout through it. With none, the terminal cards'
    /// backing (the window's tint and the card's fill) lies over the glass, so the panel reads as a card over any page.
    /// Classic: solid, as a tip.
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
            content.background(look.cardFill, in: shape).background(look.window, in: shape)
                .glassEffect(.regular, in: shape)
        }
    }
}
