import SwiftUI

struct NoticeCapsule<Action: View>: View {
    let tone: Notice.Tone
    let text: String
    var symbol: String?
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
            Text(text).lineLimit(2)
            action
        }
        .buttonBorderShape(.capsule)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .floatingGlass(in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
