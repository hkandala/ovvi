import SwiftUI

/// Ovvi's mark (resources/branding): three front-facing rounded panes stepping down to the right, charcoal, gray and
/// pearl, on the icon's dark tile. Drawn from `ovvi-flat-stack-original.png`, measured in its 1254 px. The first
/// `placed` panes stand in the stack; the others wait a small step up and to the left, clear, so the intro deals them
/// in. At -1 the tile waits too, a little smaller.
struct OvviMark: View {
    let size: CGFloat
    var placed = 3

    var body: some View {
        let unit = size / 1254
        ZStack(alignment: .topLeading) {
            let tile = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            // A faint rim, so the dark tile holds its edge on a dark panel.
            tile.fill(Look.mark.tile).overlay(tile.strokeBorder(Look.mark.rim, lineWidth: max(0.5, size / 160)))
                .opacity(placed < 0 ? 0 : 1).scaleEffect(placed < 0 ? 0.9 : 1)
            ForEach(0 ..< 3, id: \.self) { index in
                let shown = index < placed
                pane(index, unit: unit)
                    .offset(x: CGFloat(237 + 112 * index) * unit, y: CGFloat(289 + 134 * index) * unit)
                    .offset(x: shown ? 0 : -90 * unit, y: shown ? 0 : -108 * unit)
                    .scaleEffect(shown ? 1 : 0.94)
                    .opacity(shown ? 1 : 0)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// A pane, and for the front two the tile's gap round it, which cuts into the pane behind as it comes in.
    private func pane(_ index: Int, unit: CGFloat) -> some View {
        let gap = 15 * unit, width = 560 * unit, height = 394 * unit
        let colors = Look.mark.panes[index]
        return RoundedRectangle(cornerRadius: 64 * unit, style: .continuous)
            .fill(LinearGradient(colors: [colors.top, colors.bottom], startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: height)
            .background {
                if index > 0 {
                    RoundedRectangle(cornerRadius: 64 * unit + gap, style: .continuous).fill(Look.mark.tile)
                        .padding(-gap)
                }
            }
    }
}

extension Look {
    /// The mark's own colors, the same in every look (the app icon's): its tile, the tile's rim and each pane's top and
    /// bottom.
    static let mark = (tile: Color(hex: 0x1B1B1D), rim: Color(hex: 0xFFFFFF).opacity(0.12), panes: [
        (top: Color(hex: 0x545456), bottom: Color(hex: 0x37363A)),
        (top: Color(hex: 0xA2A3A7), bottom: Color(hex: 0x7C7E83)),
        (top: Color(hex: 0xF4F2EF), bottom: Color(hex: 0xE6E4E2)),
    ])
}
