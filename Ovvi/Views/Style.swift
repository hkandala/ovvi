import HerdrKit
import SwiftUI

nonisolated let gap: CGFloat = 8

extension Animation {
    /// CI's Mac has Reduce Motion on.
    private static let forceMotion = UserDefaults.standard.bool(forKey: "forceMotion")

    static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !forceMotion
    }
}

/// Values from Rex's Glass (Modern) and Classic (System) material files, tuned by eye.
struct Look: Equatable {
    let style: InterfaceStyle
    let dark: Bool
    /// The system's own colors follow Increase Contrast by themselves.
    var contrast = false
    static let onAccent = Color.white

    var backdrop: Color {
        dark ? .black.opacity(0.6) : .clear
    }

    /// A plain tint, not Liquid Glass, which costs WindowServer about a quarter more GPU time over the whole window.
    var window: Color {
        pick(Color(white: 0x1D / 255).opacity(0.845), .white.opacity(0.7),
             Color(white: 0x1E / 255), Color(white: 0xF6 / 255))
    }

    /// A flat color: a hierarchical fill on the glass panel is vibrant and shows at about a fifth of its strength.
    var paletteField: Color {
        dark ? .white.opacity(0.08) : .black.opacity(0.06)
    }

    var cardFill: Color {
        pick(.white.opacity(0.03), .white.opacity(0.6), .white.opacity(0.018), .white.opacity(0.6))
    }

    /// Classic's is exact; Glass's is measured on the screen over a black window (light Glass is the same over a white
    /// one).
    /// ponytail: a bright window or wallpaper behind lightens dark Glass's card by up to 18 levels, and the header then
    /// shows darker; an opaque card body under web cards if that matters.
    func cardSolid(keyboard: Bool = false) -> Color {
        let level = keyboard ? pick(0x23, 0xF5, 0x1F, 0xFD) : pick(0x1F, 0xF1, 0x22, 0xFB)
        return Color(white: Double(level) / 255)
    }

    var keyboardFill: Color {
        pick(.white.opacity(0.02), .white.opacity(0.25), .black.opacity(0.1), .white.opacity(0.5))
    }

    /// Dark matches Rex's Retina pixels: the line about 45 steps over the card, the sides 15.
    var rim: (all: Color, top: Color) {
        pick(
            (.white.opacity(0.06), .white.opacity(0.09)),
            (.white.opacity(0.04), .white.opacity(0.3)),
            (.clear, .clear),
            (.clear, .clear),
        )
    }

    func edge(keyboard: Bool) -> (color: Color, width: CGFloat) {
        pick((.black.opacity(0.5), 1), (.black.opacity(0.1), 1),
             keyboard ? (.white.opacity(0.16), 0.8) : (.white.opacity(0.1), 0.7),
             keyboard ? (.black.opacity(0.18), 0.8) : (.black.opacity(0.14), 0.7))
    }

    var activeBorder: Color {
        dark ? .white.opacity(0.3) : .black.opacity(0.22)
    }

    /// 3.3:1 or more on the window.
    var grip: Color {
        paneButton
    }

    /// The card shadow's color, at `dropRadius` and `dropDown` pt: Glass light only.
    var cardDrop: Color? {
        style == .glass && !dark ? .black.opacity(0.1) : nil
    }

    static let dropRadius: CGFloat = 5, dropDown: CGFloat = 2

    var track: Color {
        .primary.opacity(contrast ? 0.1 : 0.05)
    }

    var chrome: Color {
        (dark ? Color.white : .black).opacity(contrast ? 0.85 : 0.65)
    }

    var divider: Color {
        dark ? .white.opacity(contrast ? 0.3 : 0.17) : .black.opacity(contrast ? 0.28 : 0.14)
    }

    var selected: Color {
        (dark ? Color.white : .black).opacity(contrast ? 1 : 0.9)
    }

    /// 3.3:1 or more on the card.
    var paneButton: Color {
        (dark ? Color.white : .black).opacity(dark ? (contrast ? 0.6 : 0.42) : (contrast ? 0.65 : 0.45))
    }

    /// The states' colors are t3code's (Tailwind's blue, orange and emerald).
    var working: Color {
        dark ? Color(hex: 0x60A5FA) : Color(hex: 0x3B82F6)
    }

    var needsYou: Color {
        dark ? Color(hex: 0xFB923C) : Color(hex: 0xEA580C)
    }

    var finished: Color {
        dark ? Color(hex: 0x34D399) : Color(hex: 0x10B981)
    }

    var error: Color {
        dark ? Color(hex: 0xF85149) : Color(hex: 0xCF222E)
    }

    /// As macOS Messages draws them (ChatKit's `CKBlueBalloonColor1` and gray balloon).
    var sentBubble: Color {
        contrast ? Color(hex: 0x0040DD) : dark ? Color(hex: 0x0091FF) : Color(hex: 0x0088FF)
    }

    /// A Settings page's icon tile; its fill and edge go from top to bottom.
    var settingsGlyph: Color {
        dark ? Color(white: 236 / 255) : Color(hex: 0x48484E)
    }

    var settingsFill: [Color] {
        dark ? [Color(hex: 0x505056), Color(hex: 0x36363B)] : [.white, Color(hex: 0xECECF0)]
    }

    var settingsEdge: [Color] {
        dark ? [.white.opacity(0.22), .white.opacity(0.05)] : [.black.opacity(0.1), .black.opacity(0.16)]
    }

    var settingsShadow: Color {
        .black.opacity(dark ? 0.35 : 0.08)
    }

    var receivedBubble: Color {
        dark ? Color(hex: 0x3B3B3D) : Color(hex: 0xE5E5EA)
    }

    private func pick<Value>(_ glassDark: Value, _ glassLight: Value, _ classicDark: Value,
                             _ classicLight: Value) -> Value
    {
        switch (style, dark) {
        case (.glass, true): glassDark
        case (.glass, false): glassLight
        case (.classic, true): classicDark
        case (.classic, false): classicLight
        }
    }
}

extension EnvironmentValues {
    @Entry var look = Look(style: .glass, dark: true)
    @Entry var litCard = false
}

extension Color {
    init(hex: String?) {
        self.init(hex: hex.flatMap { Int($0.dropFirst(), radix: 16) } ?? 0x2B2D31)
    }

    init(hex: Int) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

struct CardSurface: View {
    static let radius: CGFloat = 10
    static let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    let keyboard: Bool
    @Environment(\.look) private var look

    var body: some View {
        let shape = Self.shape, edge = look.edge(keyboard: keyboard)
        shape.fill(look.cardFill)
            // On an opaque copy cut out under the card: on the translucent fill it would be as faint as the fill.
            .background {
                if let drop = look.cardDrop {
                    let shadow = ShadowStyle.drop(color: drop, radius: Look.dropRadius, y: Look.dropDown)
                    // An overlay does not cut (it darkens the card by about black 0.1); a ZStack does.
                    ZStack { shape.fill(Color.black.shadow(shadow)); shape.fill(.black).blendMode(.destinationOut) }
                        .compositingGroup()
                }
            }
            .overlay(shape.fill(keyboard ? look.keyboardFill : .clear))
            .overlay {
                ZStack(alignment: .top) {
                    shape.strokeBorder(look.rim.all, lineWidth: 0.7)
                    shape.strokeBorder(look.rim.top).mask(alignment: .top) {
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 14)
                    }
                    LinearGradient(colors: [look.rim.top.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                }
                .clipShape(shape).blendMode(.plusLighter)
            }
            .overlay(shape.inset(by: -edge.width / 2).stroke(edge.color, lineWidth: edge.width))
    }
}

struct Pill: View {
    let shape: RoundedRectangle
    @Environment(\.look) private var look

    var body: some View {
        switch (look.style, look.dark) {
        case (.glass, _):
            Color.clear.glassEffect(.regular, in: shape)
        case (.classic, true):
            shape.fill(.white.opacity(0.07)).overlay(shape.strokeBorder(.white.opacity(0.12)))
        case (.classic, false):
            shape.fill(.white)
                .overlay(shape.strokeBorder(.black.opacity(0.1)))
                .shadow(color: .black.opacity(0.15), radius: 3.5, y: 1.5)
        }
    }
}

struct MenuRow: View {
    let item: FilterList.Item
    let selected: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            if let state = item.state {
                StateIcon(state: state, color: selected ? .white : nil).frame(width: 22)
            } else {
                Image(symbol: item.symbol ?? "circle").opacity(item.symbol == nil ? 0 : 1).frame(width: 22)
                    .accessibilityHidden(true)
            }
            Text(item.title).lineLimit(1).truncationMode(.middle).layoutPriority(1)
            Spacer(minLength: 4)
            if item.busy {
                ProgressView().controlSize(.small)
            } else {
                Text(item.detail)
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : .secondary).lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .foregroundStyle(selected ? Color.white : .primary)
        .padding(.horizontal, 8)
        .frame(height: height)
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowButton(configuration: configuration)
    }

    private struct RowButton: View {
        let configuration: Configuration
        @Environment(\.look) private var look

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label.font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(configuration.role == .destructive ? look.error.opacity(pressed ? 0.75 : 1)
                    : .white.opacity(pressed ? 0.35 : 0.2), in: .capsule)
        }
    }
}

extension View {
    /// A plain element's value reaches XCUITest only with the static text trait.
    func readableText(_ value: String) -> some View {
        accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityValue(value)
    }

    /// The system glass over a material: Liquid Glass alone is thin on a small panel, and a terminal reads clearly
    /// through the hover card.
    func floatingGlass(in shape: some Shape) -> some View {
        glassEffect(.regular, in: shape).background(.regularMaterial, in: shape)
    }

    func floatingPanel(open: Binding<Bool>, alignment: Alignment) -> some View {
        Color.clear.contentShape(.rect).onTapGesture { open.wrappedValue = false }
            .overlay(alignment: alignment) {
                self
                    .onExitCommand { open.wrappedValue = false }
            }
    }

    func fadeEdges(_ axis: Axis, start: CGFloat, end: CGFloat) -> some View {
        let horizontal = axis == .horizontal
        let (from, until): (UnitPoint, UnitPoint) = horizontal ? (.leading, .trailing) : (.top, .bottom)
        let stack = horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        return mask {
            stack {
                LinearGradient(colors: [.clear, .black], startPoint: from, endPoint: until)
                    .frame(width: horizontal ? start : nil, height: horizontal ? nil : start)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: from, endPoint: until)
                    .frame(width: horizontal ? end : nil, height: horizontal ? nil : end)
            }
        }
    }

    func fadesScrolledEdges(end: CGFloat = 18) -> some View {
        modifier(ScrolledFades(end: end))
    }
}

extension Shape where Self == RoundedRectangle {
    static var panel: Self {
        .rect(cornerRadius: 14)
    }
}

private struct ScrolledFades: ViewModifier {
    let end: CGFloat
    @State private var under = (top: false, bottom: false)

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: [Bool].self) { geometry in
                [geometry.contentOffset.y > 0.5,
                 geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 0.5]
            } action: {
                under = ($1[0], $1[1])
            }
            .fadeEdges(.vertical, start: under.top ? 18 : 0, end: under.bottom ? end : 0)
    }
}

/// Measured on the palette's glass, where SwiftUI's hierarchical styles are fuller than AppKit's label colors, but with
/// Increase Contrast.
@MainActor
enum RowInk {
    static let primary = ink(1, 1, .labelColor), secondary = ink(0.4, 0.42, .secondaryLabelColor),
               tertiary = ink(0.27, 0.31, .tertiaryLabelColor)
    static func white(_ alpha: CGFloat) -> NSColor {
        .white.withAlphaComponent(alpha)
    }

    struct Cap { let fill: NSColor, rim: [CGFloat], sides: CGFloat; var outline: NSColor? }

    static func cap(dark: Bool, lit: Bool) -> Cap {
        let fill = NSColor.white.withAlphaComponent(lit ? dark ? 0.07 : 0.4 : dark ? 0.13 : 0)
        return dark ? Cap(fill: fill, rim: [0.42, 0.2, 0.07], sides: 0)
            : Cap(fill: fill, rim: [1, 1, 0.6], sides: 0.3, outline: .black.withAlphaComponent(0.09))
    }

    private static func ink(_ dark: CGFloat, _ light: CGFloat, _ system: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? system
                : appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white.withAlphaComponent(dark)
                : .black.withAlphaComponent(light)
        }
    }
}
