import SwiftUI

struct FadeText: View {
    let text: Text

    var body: some View {
        ViewThatFits(in: .horizontal) {
            text.fixedSize()
            text.fixedSize().frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .fadeEdges(.horizontal, start: 0, end: 16)
        }
        .lineLimit(1)
    }
}

struct Keycap: View {
    let cap: String

    var body: some View {
        Text(cap).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 22)
            .background(.quaternary, in: .rect(cornerRadius: 5))
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var key: KeyboardShortcut?
    var size: CGFloat = 28
    var accent = false
    let action: () -> Void

    var body: some View {
        let help = key.map { "\(help) \($0.glyphs)" } ?? help
        Button(action: action) {
            Image(symbol: symbol)
                .font(size < 28 ? .system(size: 11) : .body.weight(.medium))
                .foregroundStyle(accent ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.primary))
                .frame(width: size, height: size)
                .background {
                    if accent {
                        Circle().fill(.tint.opacity(0.07))
                    }
                }
        }
        .buttonStyle(ChromeStyle(radius: size / 4))
        .help(help)
        .accessibilityLabel(help)
    }
}

extension NSApplication {
    /// By AppKit's count from the events' times: SwiftUI's `TapGesture(count: 2)` misses one while the app is busy
    /// drawing the first click.
    var isDoubleClick: Bool {
        currentEvent.map { $0.type == .leftMouseUp && $0.clickCount == 2 } == true
    }
}

struct Segments<Value: Hashable>: View {
    let id: String
    let options: [(String, Value)]
    @Binding var selection: Value
    var symbols: [String: String] = [:]
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { title, value in
                Button { selection = value } label: {
                    if let symbol = symbols[title] {
                        Image(symbol: symbol).font(.system(size: 11)).frame(width: 26, height: 20)
                            .foregroundStyle(selection == value ? AnyShapeStyle(.primary) :
                                AnyShapeStyle(look.paneButton))
                    } else {
                        Text(title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).frame(height: 20)
                    }
                }
                .buttonStyle(ChromeStyle(selected: selection == value, radius: 6))
                .help(symbols[title] == nil ? "" : title)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
                .accessibilityIdentifier("\(id).\(title.lowercased())")
            }
        }
        .padding(2)
        .background(look.track, in: .rect(cornerRadius: 8))
    }
}
