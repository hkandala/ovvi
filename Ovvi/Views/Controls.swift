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
        Text(cap).font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 22)
            .background(.quaternary, in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.tertiary, lineWidth: 0.5))
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var key: KeyboardShortcut?
    var size: CGFloat = 28
    /// The glyph's size in a small button: symbols differ in ink, so a row can even them out.
    var glyph: CGFloat = 11
    var accent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(symbol: symbol)
                .font(size < 28 ? .system(size: glyph) : .body.weight(.medium))
                .foregroundStyle(accent ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.primary))
                .frame(width: size, height: size)
                .background(.tint.opacity(accent ? 0.07 : 0), in: .rect(cornerRadius: size / 4, style: .continuous))
        }
        .buttonStyle(ChromeStyle(radius: size / 4))
        .tip(help, key: key)
        .accessibilityLabel(key.map { "\(help) \($0.glyphs)" } ?? help)
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
                .tip(symbols[title] == nil ? "" : title)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
                .accessibilityIdentifier("\(id).\(title.lowercased())")
            }
        }
        .padding(2)
        .background(look.track, in: .rect(cornerRadius: 8))
    }
}
