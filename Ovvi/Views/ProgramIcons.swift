import HerdrKit
import SwiftUI

/// The program icon catalog (`resources/icons/catalog.json`, bundled).
let programIcons: [ProgramIcon] = {
    // Without it every pane would draw the neutral tile: loud in a debug build.
    guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
        assertionFailure("no catalog.json in the app")
        return []
    }
    do {
        return try JSONDecoder().decode([ProgramIcon].self, from: Data(contentsOf: url))
    } catch {
        assertionFailure("program icon catalog: \(error)")
        return []
    }
}()

/// A program's colored tile, as in Rex: the catalog's tile and glyph colors, a dark outline and a faint highlight
/// at the top.
struct ProgramTile: View {
    let icon: String
    /// The placeholder's: the program's first letter.
    var letter: String?
    @Environment(\.displayScale) private var scale

    var body: some View {
        // A browser's or a plugin's symbol is no catalog icon: a generic tool's glyph, on the shell's tile.
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
            // Rex's tiles are quieter than the catalog's colors.
            .saturation(0.82)
            .brightness(-0.04)
            .accessibilityHidden(true)
    }
}

/// A page's symbol on its tile, as Raycast draws its settings (the user's pick, option b): a lifted tile of the
/// sidebar's own tone, lit from the top with a fine rim, and a filled two-tone symbol; dark tiles in dark, light tiles
/// in light. Fixed colors (they change only with light and dark, never with the Look's style), drawn as one layer,
/// which the sidebar's selection does not tint.
struct SettingsIcon: View {
    let page: SettingsPage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Image(systemName: page.symbol).font(.system(size: 13, weight: .medium)).imageScale(.medium)
            .symbolVariant(.fill).symbolRenderingMode(.hierarchical)
            .foregroundStyle(dark ? Color(white: 236 / 255) : Color(red: 72 / 255, green: 72 / 255, blue: 78 / 255))
            .frame(width: 22, height: 22)
            .background(LinearGradient(colors: dark ? [Color(red: 80 / 255, green: 80 / 255, blue: 86 / 255),
                                                       Color(red: 54 / 255, green: 54 / 255, blue: 59 / 255)]
                    : [.white, Color(red: 236 / 255, green: 236 / 255, blue: 240 / 255)],
                startPoint: .top, endPoint: .bottom), in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: dark ? [.white.opacity(0.22), .white.opacity(0.05)]
                    : [.black.opacity(0.10), .black.opacity(0.16)],
                startPoint: .top, endPoint: .bottom), lineWidth: 0.5))
            .shadow(color: .black.opacity(dark ? 0.35 : 0.08), radius: 0.5, y: 0.5)
            .compositingGroup()
    }
}

/// The program's glyph alone, for card headers, hover card rows and an empty chat.
struct ProgramGlyph: View {
    let icon: String
    var letter: String?
    var size: CGFloat = 16

    var body: some View {
        ProgramMark(icon: icon, letter: letter, size: size).foregroundStyle(.secondary).accessibilityHidden(true)
    }
}

/// The catalog's template image, or the placeholder's letter, in the same square: names after it line up.
private struct ProgramMark: View {
    let icon: String
    let letter: String?
    let size: CGFloat

    var body: some View {
        Group {
            if icon == "placeholder", let letter {
                Text(letter).font(.system(size: size * 0.65, weight: .bold, design: .rounded))
            } else if Registry.symbols.contains(icon) {
                // A browser's or a plugin's (ui/browser): the system's symbol, on the neutral tile.
                Image(symbol: icon).resizable().scaledToFit().padding(size * 0.12)
            } else {
                Image("program.\(icon)").resizable()
            }
        }
        .frame(width: size, height: size)
    }
}

/// A tab's panes as overlapping tiles, the first in front and each next one 4 pt to the right behind it. A ring cut
/// around each tile in front keeps the layers apart on any background.
struct IconStack: View {
    let panes: [HostStore.Pane]

    var body: some View {
        ZStack(alignment: .leading) {
            // A new tab before herdr has it (`Ahead`).
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
        .frame(width: 22 + CGFloat(max(panes.count - 1, 0)) * 4, alignment: .leading)
    }
}
