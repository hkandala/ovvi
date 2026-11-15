import SwiftUI

struct NoticeCapsule<Action: View>: View {
    let tone: Notice.Tone
    let text: String
    var symbol: String?
    /// The whole text, on hover, when `text` is one line of it.
    var whole: String?
    /// A smaller text after it, such as the reason a machine is reconnecting.
    var detail = ""
    @ViewBuilder var action: Action
    @Environment(\.look) private var look

    var body: some View {
        let (toneSymbol, label, color) = switch tone {
        case .error: ("xmark.octagon.fill", "Error", look.error)
        case .warning: ("exclamationmark.triangle.fill", "Warning", look.needsYou)
        case .info: ("info.circle.fill", "Information", look.working)
        case .progress: ("", "In progress", look.working)
        case .success: ("checkmark.circle.fill", "Done", look.finished)
        }
        Capped(width: Notice.width) {
            HStack(spacing: 8) {
                Group {
                    if tone == .progress {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: symbol ?? toneSymbol).foregroundStyle(color)
                    }
                }
                .accessibilityLabel(label)
                .accessibilityIdentifier("notice.symbol")
                // One line: what is longer ends in … and shows whole on hover.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(text).lineLimit(1).help(whole ?? text).accessibilityLabel(whole ?? text).layoutPriority(1)
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).help(detail)
                            .accessibilityIdentifier("notice.detail")
                    }
                }
                action
            }
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 14)
        }
        .frame(minHeight: 36)
        .floatingGlass(in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
