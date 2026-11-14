import SwiftUI

struct NoticeCapsule<Action: View>: View {
    let tone: Notice.Tone
    let text: String
    var symbol: String?
    /// A smaller second line, such as the reason a machine is reconnecting.
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(text).lineLimit(2).help(text)
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).help(detail)
                            .accessibilityIdentifier("notice.detail")
                    }
                }
                action
            }
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 14)
            .padding(.vertical, detail.isEmpty ? 0 : 8)
        }
        .frame(minHeight: 36)
        .floatingGlass(in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
