import SwiftUI

enum WelcomePage {
    case hello, panes, agents, machines, herdr
}

/// One page: a headline, then close-ups of the app's own parts (pictures in Welcome.xcassets, made by
/// scripts/welcome-pictures), each with a line under it. They rise one after another as the page comes in, then each
/// moves in closer in its turn.
struct WelcomePageView: View {
    let page: WelcomePage
    let forward: Bool
    let still: Bool
    @Binding var herdrFound: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 26, weight: .semibold)).tracking(-0.3)
                .modifier(Rise(order: 0, forward: forward, still: still))
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var title: String {
        switch page {
        case .hello: "Welcome to Ovvi"
        case .panes: "Panes, tabs and spaces"
        case .agents: "Agents and plugins"
        case .machines: "Your machines"
        case .herdr: "One more thing"
        }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .hello:
            // The zoom ends on the sidebar and the agent's chat, whole.
            item(1, [Shot("hero", shown: 820, focus: CGRect(x: 0, y: 110, width: 750, height: 0))],
                 "Your terminals, agents and tools side by side, in one window. They run in sessions, so they keep "
                     + "going when you close the window or quit Ovvi.", width: 580)
        case .panes:
            VStack(spacing: 20) {
                item(1, [Shot("tabs", shown: 760)], "**Tabs** hold sets of panes and show what runs in each.",
                     keys: [KeyboardShortcut.newTab.glyphs, "⌘1…⌘9"])
                HStack(alignment: .top, spacing: 56) {
                    item(2, [Shot("chooser", shown: 330)], "A new pane asks what to run. Split right or down.",
                         keys: [KeyboardShortcut.splitRight.glyphs, KeyboardShortcut.splitDown.glyphs])
                    item(3, [Shot("spaces", shown: 230)],
                         "**Spaces**: one per project. Orange needs you, blue works, green is done.", width: 280,
                         keys: [KeyboardShortcut.newWorkspace.glyphs, "⌃⌘1…⌃⌘9"])
                }
            }
        case .agents:
            HStack(alignment: .top, spacing: 24) {
                item(1, [Shot("chat", shown: 280)],
                     "**Claude Code, Codex, Pi or OpenCode**, in a terminal or as a chat: the same agent either way.")
                // A stack, as the mark's panes: each card's top shows what it is.
                item(2, ["browser", "git", "files"].map { Shot($0, shown: 210, stacked: true) },
                     "**Browser, Git and File Explorer** come with Ovvi.", width: 260)
                item(3, [Shot("plugin", shown: 262)], "**Your own plugins**: small TypeScript packages. New Plugin… "
                    + "starts one; your agent can too, with `ovvi`.")
            }
        case .machines:
            HStack(alignment: .center, spacing: 56) {
                item(1, [Shot("menu", shown: 152)],
                     "**Any machine you can ssh to**, from the machine menu. Your SSH config works as it is.",
                     width: 330)
                item(2, [Shot("machines", shown: 460)],
                     "Its sessions open in a window of their own, and keep running while your Mac sleeps.")
            }
        case .herdr:
            HerdrStep(found: $herdrFound).modifier(Rise(order: 1, forward: forward, still: still))
        }
    }

    private func item(_ order: Int, _ shots: [Shot], _ words: String, width: CGFloat? = nil,
                      keys: [String] = []) -> some View
    {
        let label = words.replacing("**", with: "").replacing("`", with: "")
        return VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                ForEach(shots.indices, id: \.self) { index in
                    Cutout(shot: shots[index], label: label, closer: still ? nil : 0.9 + 0.7 * Double(order - 1))
                        .padding(.leading, CGFloat(index) * 44).padding(.top, CGFloat(index) * 60)
                        .modifier(Rise(order: Double(order) + 0.8 * Double(index), forward: forward, still: still))
                }
            }
            VStack(spacing: 10) {
                Text(.init(words)).font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .lineSpacing(2).frame(maxWidth: width ?? shots[0].shown).fixedSize(
                        horizontal: false,
                        vertical: true,
                    )
                if !keys.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(keys, id: \.self) { Keycap(text: $0) }
                    }
                }
            }
            .modifier(Rise(order: Double(order), forward: forward, still: still))
        }
    }
}

/// A picture of one part of the app (Welcome.xcassets, light and dark; its size in the app's points is the image's),
/// the width it is shown at, and the part it moves in on: `focus`, in the picture's points (its height follows the
/// picture's shape), zooms within the picture to that part, which ends on whole things; else the picture itself
/// comes closer, to the size it rests at. A stacked one stays as it is.
struct Shot {
    let name: String
    let shown: CGFloat
    var focus: CGRect?
    var stacked = false

    init(_ name: String, shown: CGFloat, focus: CGRect? = nil, stacked: Bool = false) {
        self.name = name
        self.shown = shown
        self.focus = focus
        self.stacked = stacked
    }
}

/// A shot cut out: rounded, with a hairline edge and a soft shadow, floating on the panel. After `closer` seconds it
/// moves in: a zoom within to its focus, or the whole picture from a step smaller to its full size.
struct Cutout: View {
    let shot: Shot
    let label: String
    let closer: Double?
    @State private var near = false
    @Environment(\.look) private var look

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let edge = look.edge(keyboard: false)
        let (zoom, anchor) = shot.focus.map { Self.zoom(
            to: $0,
            in: NSImage(named: "welcome/\(shot.name)")?.size ?? .zero,
        ) }
            ?? (1, .center)
        Image("welcome/\(shot.name)").resizable().interpolation(.high).scaledToFit()
            .scaleEffect(near ? zoom : 1, anchor: anchor)
            .frame(width: shot.shown).clipShape(shape)
            .overlay(shape.strokeBorder(edge.color, lineWidth: edge.width))
            // On a still shape behind the picture: a shadow of the zooming picture itself is drawn again each frame.
            .background(shape.fill(look.cardSolid()).shadow(color: look.floatShadow, radius: 16, y: 8))
            .scaleEffect(near || shot.focus != nil || shot.stacked || closer == nil ? 1 : 0.92)
            .accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityIdentifier("welcome.picture")
            .accessibilityLabel(label).accessibilityValue("\(shot.name) \(look.dark ? "dark" : "light")")
            .onAppear {
                guard let closer, !shot.stacked else { return }
                withAnimation(.spring(duration: 1.4, bounce: 0.05).delay(closer)) { near = true }
            }
    }

    /// The scale and anchor that fill the frame with `focus`: after a scale `s` about anchor `a`, the frame shows the
    /// picture from `a × (size − size / s)`, `size / s` long.
    static func zoom(to focus: CGRect, in size: CGSize) -> (CGFloat, UnitPoint) {
        guard focus.width < size.width else { return (1, .center) }
        let zoom = size.width / focus.width, height = size.height / zoom
        return (zoom, UnitPoint(x: focus.minX / (size.width - focus.width), y: focus.minY / (size.height - height)))
    }
}

private struct Keycap: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).fixedSize().frame(minWidth: 13)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .glassEffect(.regular, in: .rect(cornerRadius: 5))
    }
}

/// Comes in after the ones before it (`order`): from the side the page turns from and a little below, on a spring.
private struct Rise: ViewModifier {
    let order: Double
    let forward: Bool
    let still: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        let away = !shown && !still
        content.opacity(shown ? 1 : 0)
            .offset(x: away ? (forward ? 34 : -34) : 0, y: away ? 14 : 0)
            .onAppear {
                let rise: Animation = still ? .easeOut(duration: 0.3)
                    : .spring(duration: 0.6, bounce: 0.2).delay(0.14 + 0.07 * order)
                withAnimation(rise) { shown = true }
            }
    }
}
