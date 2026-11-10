import HerdrKit
import SwiftUI

struct ProgramTile: View {
    let icon: String
    var letter: String?
    @Environment(\.displayScale) private var scale

    var body: some View {
        let colors = programIcons.first { $0.id == (Registry.symbols.contains(icon) ? "terminal" : icon) }?.tile
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        // The glyphs carry their own padding in a 24 pt box.
        ProgramMark(icon: icon, letter: letter, size: 17)
            .foregroundStyle(Color(hex: colors?.glyph))
            .frame(width: 22, height: 18)
            .background(Color(hex: colors?.background), in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top,
                                                       endPoint: .center), lineWidth: 1))
            .overlay(shape.inset(by: -0.5 / scale).stroke(.black.opacity(0.45), lineWidth: 1 / scale))
            .saturation(0.82)
            .brightness(-0.04)
            .accessibilityHidden(true)
    }
}

struct ProgramGlyph: View {
    let icon: String
    var letter: String?
    var size: CGFloat = 16

    var body: some View {
        ProgramMark(icon: icon, letter: letter, size: size).foregroundStyle(.secondary).accessibilityHidden(true)
    }
}

private struct ProgramMark: View {
    let icon: String
    let letter: String?
    let size: CGFloat

    var body: some View {
        Group {
            if icon == "placeholder", let letter {
                Text(letter).font(.system(size: size * 0.65, weight: .bold, design: .rounded))
            } else if Registry.symbols.contains(icon) {
                Image(symbol: icon).resizable().scaledToFit().padding(size * 0.12)
            } else {
                Image("program.\(icon)").resizable()
            }
        }
        .frame(width: size, height: size)
    }
}

struct IconStack: View {
    let panes: [HostStore.Pane]

    var body: some View {
        ZStack(alignment: .leading) {
            if panes.isEmpty {
                ProgramTile(icon: "terminal")
            }
            ForEach(Array(panes.enumerated()).reversed(), id: \.element.id) { index, pane in
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).frame(width: 24, height: 20)
                        .blendMode(.destinationOut)
                    ProgramTile(icon: pane.iconID, letter: pane.letter)
                }
                .frame(width: 22, height: 18)
                .offset(x: CGFloat(index) * 4)
            }
        }
        .compositingGroup()
        .frame(width: Self.width(panes.count), alignment: .leading)
    }

    static func width(_ count: Int) -> CGFloat {
        22 + CGFloat(max(count - 1, 0)) * 4
    }
}
