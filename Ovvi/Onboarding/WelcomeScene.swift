import SwiftUI

/// The welcome's picture: one Ovvi window, drawn, that grows page by page out of pieces of real screenshots
/// (Welcome.xcassets, made by scripts/welcome-pictures): one pane, a split, the tab bar and the sidebar, an agent and
/// plugins, then a second window on another machine. A piece that stays moves to its new place; one that comes slides
/// in. Reduce Motion: the finished scenes cross-fade (`WelcomeView`).
struct WelcomeScene: View {
    /// 1 to 5: the story's pages; 6: the herdr step, the windows gone.
    let stage: Int
    let intro: Intro
    /// The camera has moved in on what the page's words are about (`focus`).
    let zoomed: Bool
    /// The pictures of the stages up to this one are drawn: decoded while a page stands still, not as the next comes.
    let loaded: Int
    let reduceMotion: Bool
    @Environment(\.look) private var look

    /// The screenshots' window, in points; the scene shows it at `scale`, and zooms in up to 1.5: a drawn point keeps
    /// the screenshots' 2 pixels.
    static let window = CGSize(width: 1320, height: 590)
    static let scale: CGFloat = 2 / 3
    /// Where the window sits in the panel: it fills the scene's view, which cuts off what a zoom pushes out.
    static let origin = CGPoint(x: 40, y: 24)
    static let view = CGRect(origin: origin, size: CGSize(width: window.width * scale, height: window.height * scale))
    /// The last page's two windows, each with its machine's label.
    static let machines = (mac: CGPoint(x: 56, y: 64), remote: CGPoint(x: 330, y: 146), scale: CGFloat(0.42))

    /// Per stage, the point the camera zooms in on (in the window's points) and how far: the dev server's log, the
    /// pane that asks what it runs, the sidebar, the agent. The last page pulls back out to two windows.
    static let focus: [Int: (point: CGPoint, zoom: CGFloat)] = [
        1: (CGPoint(x: 0, y: 0), 1.3),
        2: (CGPoint(x: 1320, y: 590), 1.45),
        3: (CGPoint(x: 0, y: 0), 1.4),
        4: (CGPoint(x: 560, y: 0), 1.45),
    ]

    var body: some View {
        let last = stage >= 5, gone = stage == 6, machines = Self.machines
        ZStack(alignment: .topLeading) {
            window(pieces: Piece.main, stage: min(stage, 4), at: last ? machines.mac : Self.origin,
                   scale: last ? machines.scale : Self.scale)
            window(pieces: Piece.remote, stage: last ? 5 : 0, at: CGPoint(x: machines.remote.x + (last ? 0 : 80),
                                                                          y: machines.remote.y), scale: machines.scale)
                .opacity(stage == 5 ? 1 : 0)
                .animation(spring?.delay(stage == 5 ? 0.25 : 0), value: stage)
            // Which machine each window shows, above it.
            label("This Mac", "laptopcomputer").offset(x: machines.mac.x, y: machines.mac.y - 30)
            label("build-server", "server.rack")
                .frame(width: Self.window.width * machines.scale, alignment: .trailing)
                .offset(x: machines.remote.x, y: machines.remote.y - 30)
        }
        .frame(width: Welcome.size.width, height: Welcome.size.height, alignment: .topLeading)
        // About the top left, moved so the focus stays put: out of a zoom needs no new focus.
        .scaleEffect(zoom.amount, anchor: .topLeading)
        .offset(x: (1 - zoom.amount) * zoom.point.x, y: (1 - zoom.amount) * zoom.point.y)
        .animation(reduceMotion ? nil : .spring(duration: 1.1, bounce: 0.05), value: zoomed)
        .mask(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16 * Self.scale, style: .continuous)
                .frame(width: Self.view.width, height: Self.view.height).offset(x: Self.view.minX, y: Self.view.minY)
        }
        .opacity(gone ? 0 : 1)
        .scaleEffect(gone ? 0.94 : 1)
        .animation(spring, value: stage)
        .frame(width: Welcome.size.width, height: Welcome.size.height, alignment: .topLeading)
    }

    /// The camera's zoom and the point that stays put, in the panel.
    private var zoom: (amount: CGFloat, point: CGPoint) {
        guard zoomed, let focus = Self.focus[stage] else { return (1, .zero) }
        return (focus.zoom, CGPoint(x: Self.origin.x + focus.point.x * Self.scale,
                                    y: Self.origin.y + focus.point.y * Self.scale))
    }

    private var spring: Animation? {
        reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.12)
    }

    private func label(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .floatingGlass(in: .capsule)
            .accessibilityHidden(true)
            .opacity(stage == 5 ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(stage == 5 ? 0.55 : 0), value: stage)
    }

    /// A window: its frame, then its pieces, laid out in the screenshots' points, put at `at` in the panel at `scale`.
    private func window(pieces: [Piece], stage: Int, at origin: CGPoint, scale: CGFloat) -> some View {
        let frame = RoundedRectangle(cornerRadius: 16, style: .continuous), shown = intro == .scene
        return ZStack(alignment: .topLeading) {
            frame.fill(look.shotWindow)
                .overlay(frame.strokeBorder(look.edge(keyboard: true).color, lineWidth: 1.5))
                .shadow(color: .primary.opacity(look.dark ? 0 : 0.08), radius: 24, y: 10)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 8) {
                        ForEach(0 ..< 3) { _ in
                            Circle().fill(.primary.opacity(0.18)).frame(width: 12, height: 12)
                        }
                    }
                    .offset(x: 18, y: 17)
                }
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(shown ? 0.15 : 0), value: shown)
            ForEach(pieces) { piece in
                PieceView(piece: piece, stage: stage, loaded: loaded, intro: piece.id == "a" ? intro : .scene,
                          reduceMotion: reduceMotion)
                    .accessibilityHidden(piece.id != "a" || stage != 1)
            }
        }
        .frame(width: Self.window.width, height: Self.window.height, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading).offset(x: origin.x, y: origin.y)
    }
}

/// A piece of a screenshot on one stage: its picture (dark and light in the catalog) and its frame in the window.
struct Piece: Identifiable {
    let id: String
    /// Per stage: the picture's name and its frame; a stage without one has the piece away, at `away`.
    let stages: [Int: (picture: String, frame: CGRect)]
    /// How far it comes in from: a pane from the right or below, the sidebar from the left, the tab bar from above.
    let away: CGSize
    /// Cards are rounded; the sidebar and the tab bar are not.
    var card = true
    /// After how long it moves on a stage, so a page plays its pieces one after another.
    var delays: [Int: Double] = [:]

    static func frame(_ left: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: left, y: top, width: width, height: height)
    }

    static let main = [
        Piece(id: "a", stages: [
            1: ("1a", frame(8, 46, 1304, 536)),
            2: ("2a", frame(8, 46, 648, 536)),
            3: ("3a", frame(300, 46, 502, 536)),
            4: ("4a", frame(300, 46, 502, 536)),
        ], away: .zero),
        Piece(id: "b", stages: [
            2: ("2b", frame(664, 46, 648, 264)),
            3: ("3b", frame(810, 46, 502, 264)),
            4: ("4b", frame(810, 46, 502, 536)),
        ], away: CGSize(width: 140, height: 0)),
        Piece(id: "c", stages: [
            2: ("2c", frame(664, 318, 648, 264)),
            3: ("3c", frame(810, 318, 502, 264)),
        ], away: CGSize(width: 0, height: 110), delays: [2: 0.45]),
        Piece(id: "sidebar", stages: [
            3: ("3s", frame(0, 46, 296, 544)),
            4: ("4s", frame(0, 46, 296, 544)),
        ], away: CGSize(width: -110, height: 0), card: false, delays: [3: 0.35]),
        Piece(id: "tabs", stages: [
            3: ("3t", frame(296, 0, 1024, 46)),
            4: ("4t", frame(296, 0, 1024, 46)),
        ], away: CGSize(width: 0, height: -36), card: false),
    ]

    static let remote = [
        Piece(id: "r", stages: [5: ("5r", frame(0, 46, 1320, 544))], away: .zero, card: false),
    ]
}

/// One piece: its picture at its own size from the top left, cut to its frame, so a pane that grows shows more of it.
private struct PieceView: View {
    let piece: Piece
    let stage: Int
    let loaded: Int
    let intro: Intro
    let reduceMotion: Bool
    @Environment(\.look) private var look

    var body: some View {
        // Away: where it was or will be, faded.
        let here = piece.stages[stage]
        let shown = here == nil ? piece.stages.keys.min { abs($0 - stage) < abs($1 - stage) } ?? 0 : stage
        let near = piece.stages[shown], rest = near?.frame ?? .zero
        let frame = intro < .scene ? Self.markFront : here == nil ? rest.offsetBy(dx: piece.away.width,
                                                                                  dy: piece.away.height) : rest
        let radius = intro < .scene ? Mark.radius / WelcomeScene.scale : piece.card ? 10 : 0
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let delay = piece.delays[stage] ?? 0
        ZStack(alignment: .topLeading) {
            // Each stage's picture is drawn, unseen, from `loaded` on, so its decode is done before its page.
            let keys = piece.stages.keys.filter { $0 <= loaded || here != nil && $0 == shown }.sorted()
            ForEach(keys, id: \.self) { key in
                let picture = piece.stages[key]
                Image("welcome.\(picture?.picture ?? "")").resizable().interpolation(.high)
                    .frame(width: picture?.frame.width, height: picture?.frame.height)
                    .opacity(key == shown && intro == .scene ? 1 : 0)
            }
            // The intro's pearl pane, which this one grows out of; it fades in place as the picture comes.
            Group {
                shape.fill(Mark.fill(2)).opacity(intro >= .fill || reduceMotion ? 1 : 0)
                    .animation(.easeOut(duration: 0.45).delay(0.24), value: intro >= .fill)
                shape.trim(from: 0, to: intro >= .outline || reduceMotion ? 1 : 0)
                    .stroke(Mark.line(drawing: intro < .fill), lineWidth: 1 / WelcomeScene.scale)
                    .animation(.easeInOut(duration: 0.6).delay(0.28), value: intro >= .outline)
            }
            .opacity(intro < .scene ? 1 : 0)
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipShape(shape)
        .overlay {
            if piece.card, intro == .scene {
                let edge = look.edge(keyboard: false)
                shape.inset(by: -edge.width / 2).stroke(edge.color, lineWidth: edge.width)
            }
        }
        .accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityIdentifier("welcome.picture")
        .accessibilityValue("welcome.\(near?.picture ?? "") \(look.dark ? "dark" : "light")")
        .opacity(here == nil || intro == .start && reduceMotion ? 0 : 1)
        .offset(x: frame.minX, y: frame.minY)
        .animation(reduceMotion ? nil : .spring(duration: 0.75, bounce: 0.12).delay(delay), value: stage)
        .animation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.1), value: intro)
        .animation(.easeInOut(duration: 0.4).delay(delay), value: shown)
    }

    /// The mark's pearl pane, in the window's points.
    static let markFront: CGRect = {
        let rect = Mark.rect(2), scale = WelcomeScene.scale, origin = WelcomeScene.origin
        return CGRect(x: (rect.minX - origin.x) / scale, y: (rect.minY - origin.y) / scale,
                      width: rect.width / scale, height: rect.height / scale)
    }()
}
