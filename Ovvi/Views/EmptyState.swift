import SwiftUI

/// The app's one look for an empty, failed or not-installed place (ui/states): a symbol, a title, one line, and at most
/// two buttons, the first one prominent. `compact` in a list or a small panel.
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    var text: String?
    /// The line is a command or a program's output: monospaced, selectable, up to 12 lines.
    var code = false
    /// A command under the line, monospaced and selectable (`<id>.command`): what the first button runs.
    var command: String?
    var compact = false
    /// The title's identifier; the line's is `<id>.text`.
    var id: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: compact ? 6 : 12) {
            Image(symbol: symbol).font(.system(size: compact ? 20 : 32, weight: .light)).foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical).accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(title).font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .identifier(id)
                if let text, !text.isEmpty {
                    Text(text).font(code ? .system(size: 12).monospaced() : .system(size: compact ? 12 : 13))
                        .foregroundStyle(.secondary).lineLimit(code ? 12 : 3).textSelection(.enabled)
                        .identifier(id.map { "\($0).text" })
                }
                if let command {
                    Text(command).font(.system(size: 12).monospaced()).foregroundStyle(.tertiary).lineLimit(2)
                        .textSelection(.enabled).padding(.top, 4).identifier(id.map { "\($0).command" })
                }
            }
            HStack(spacing: 8) { actions }
                .buttonStyle(.glass).controlSize(compact ? .regular : .large).padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
        .padding(compact ? 12 : 24)
    }
}

extension EmptyState where Actions == EmptyView {
    init(symbol: String, title: String, text: String? = nil, compact: Bool = false, id: String? = nil) {
        self.init(symbol: symbol, title: title, text: text, compact: compact, id: id) {}
    }
}

/// The app's one loader (ui/states): an icon over a small spinner and one line, after `delay` so a quick load shows
/// nothing; `detail` under it says what the work is doing (an installer's last line, a reconnect's reason).
struct Loader<Icon: View>: View {
    var text = ""
    var detail: String?
    var id: String?
    var delay = Duration.zero
    @ViewBuilder var icon: Icon
    @State private var shown = false

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                icon.font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    if !text.isEmpty {
                        Text(text).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(text.hasSuffix("…") ? String(text.dropLast()) : text)
            .identifier(id)
            if let detail, !detail.isEmpty {
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    .multilineTextAlignment(.center).frame(maxWidth: 420)
                    .identifier(id.map { "\($0).detail" })
            }
        }
        .opacity(shown ? 1 : 0)
        .task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            shown = true
        }
    }
}

extension Loader where Icon == Image? {
    /// With an SF Symbol (or one of the app's own), or none: a spinner and its line alone.
    init(symbol: String? = nil, text: String = "", detail: String? = nil, id: String? = nil,
         delay: Duration = .zero)
    {
        self.init(text: text, detail: detail, id: id, delay: delay) { symbol.map { Image(symbol: $0) } }
    }
}

private extension View {
    /// An identifier only when there is one: an empty one would hide what a caller sets around the view.
    @ViewBuilder func identifier(_ id: String?) -> some View {
        if let id {
            accessibilityIdentifier(id)
        } else {
            self
        }
    }
}
