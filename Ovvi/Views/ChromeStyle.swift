import SwiftUI

struct ChromeStyle: ButtonStyle {
    var selected = false
    var radius: CGFloat = 8
    var inset: CGFloat = 0
    var tint: Color?
    var hovered: Bool?
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
                            let lit = style.hovered ?? style.light?.lit ?? hovering
                            let strength = configuration.isPressed ? 0.08 : lit && enabled ? 0.05 : 0
                            // On the tint alone: on the whole label it fades a menu's light from row to row. A list's
                            // light does not fade: in the sidebar's lazy stack each fade keeps the main thread busy for
                            // half of a hover sweep over 200 spaces, with 100 ms frames.
                            shape.fill(.primary.opacity(strength))
                                .animation(style.light == nil ? .motion(.easeOut(duration: 0.14)) : nil, value: lit)
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
