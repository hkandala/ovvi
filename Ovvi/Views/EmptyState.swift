import SwiftUI

struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    var text: String?
    var code = false
    var command: String?
    var compact = false
    var id: String?
    @ViewBuilder var actions: Actions
    @Environment(\.pageReconnecting) private var reconnecting

    var body: some View {
        if !reconnecting {
            content
        }
    }

    private var content: some View {
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

struct Loader<Icon: View>: View {
    var text = ""
    var detail: String?
    var id: String?
    var delay = Duration.zero
    @ViewBuilder var icon: Icon
    @State private var shown = false
    @Environment(\.pageReconnecting) private var reconnecting

    var body: some View {
        if !reconnecting {
            content
        }
    }

    private var content: some View {
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
    init(symbol: String? = nil, text: String = "", detail: String? = nil, id: String? = nil,
         delay: Duration = .zero)
    {
        self.init(text: text, detail: detail, id: id, delay: delay) { symbol.map { Image(symbol: $0) } }
    }
}

private extension View {
    /// An empty identifier would hide what a caller sets around the view.
    @ViewBuilder func identifier(_ id: String?) -> some View {
        if let id {
            accessibilityIdentifier(id)
        } else {
            self
        }
    }
}
