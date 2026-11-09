import SwiftUI

struct ChromeStyle: ButtonStyle {
    var selected = false
    var radius: CGFloat = 8
    /// How far above and below the hit area's edges the fills are drawn (a tab's capsule inside its track).
    var inset: CGFloat = 0
    /// The selected fill; the look's pill when nil.
    var tint: Color?
    /// The owner's hover, for a view that moves under the pointer (a dropped tab), which sends no hover event.
    var hovered: Bool?
    /// Its light under the pointer, for a list that finds the row under the pointer itself, observed in the button's
    /// own
    /// update; then the button has no hover region of its own.
    var light: RowLight?

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
                            let lit = style.hovered ?? style.light?.lit ?? hovering
                            let strength = configuration.isPressed ? 0.08 : lit && enabled ? 0.05 : 0
                            // On the tint alone: on the whole label it also faded a menu's light from row to row
                            // (FilterList lights the hovered row).
                            // A list's light does not fade: in the sidebar's lazy stack each fade (with an
                            // animation here or where the light is set) kept the main thread busy for half of a hover
                            // sweep over 200 spaces, with 100 ms frames.
                            shape.fill(.primary.opacity(strength))
                                .animation(style.light == nil ? .easeOut(duration: 0.14) : nil, value: lit)
                        } else if let tint = style.tint {
                            shape.fill(tint)
                        } else {
                            Pill(shape: shape)
                        }
                    }
                    .padding(.vertical, style.inset)
                }
                .opacity(enabled ? 1 : 0.4)
                .onHover(if: style.hovered == nil && style.light == nil) { hovering = $0 }
        }
    }
}
