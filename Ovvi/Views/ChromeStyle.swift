import SwiftUI

/// Rows, buttons and capsules: flat at rest, a soft fill under the pointer, a raised pill when selected.
struct ChromeStyle: ButtonStyle {
    var selected = false
    var radius: CGFloat = 8
    /// How far above and below the hit area's edges the fills are drawn (a tab's capsule inside its track).
    var inset: CGFloat = 0
    /// The selected fill; the look's pill when nil.
    var tint: Color?
    /// The owner's hover, for a view that moves under the pointer (a dropped tab), which sends no hover event.
    var hovered: Bool?

    func makeBody(configuration: Configuration) -> some View {
        Chrome(style: self, configuration: configuration)
    }

    struct Chrome: View {
        let style: ChromeStyle
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: style.radius - style.inset, style: .continuous)
            configuration.label
                .contentShape(.rect(cornerRadius: style.radius))
                .background {
                    Group {
                        if !style.selected {
                            // The same in both styles, and they follow the appearance by themselves (D44).
                            let lit = style.hovered ?? hovering
                            let strength = configuration.isPressed ? 0.08 : lit && enabled ? 0.05 : 0
                            // On the tint alone: on the whole label it also faded a menu's light from row to row
                            // (FilterList lights the hovered row).
                            shape.fill(.primary.opacity(strength)).animation(.easeOut(duration: 0.14), value: lit)
                        } else if let tint = style.tint {
                            shape.fill(tint)
                        } else {
                            Pill(shape: shape)
                        }
                    }
                    .padding(.vertical, style.inset)
                }
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}
