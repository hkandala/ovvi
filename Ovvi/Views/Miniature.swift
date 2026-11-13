import AppKit
import HerdrKit
import SwiftUI

struct Miniature: View {
    let tab: HostStore.Tab
    let page: Page
    let size: CGSize
    let live: Set<String>

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / size.width, area = CGRect(origin: .zero, size: size)
            if let tree = tab.tree {
                let zoomed = page.zoomedPanes[tab.id].flatMap { tree.paneIDs.contains($0) ? $0 : nil }
                let cards = Parts(tree, in: area, held: [:]).cards.filter { zoomed == nil || $0.id == zoomed }
                ZStack(alignment: .topLeading) {
                    ForEach(cards, id: \.id) { card in
                        let rect = zoomed == nil ? card.rect : area
                        MiniCard(id: card.id, page: page, size: rect.size, scale: scale, live: live)
                            .frame(width: rect.width * scale, height: rect.height * scale)
                            .position(x: rect.midX * scale, y: rect.midY * scale)
                    }
                }
            }
        }
    }
}

private struct MiniCard: View {
    let id: String
    let page: Page
    let size: CGSize
    let scale: CGFloat
    let live: Set<String>
    @Environment(\.look) private var look

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CardSurface.radius * scale, style: .continuous),
            edge = look.edge(keyboard: false)
        let pane = page.store.pane(id), header = page.headerHeight(pane)
        let terminal = PaneCard.terminalSize(size, header: header)
        let content = CGSize(width: size.width, height: max(size.height - header, 1))
        shape.fill(look.cardFill)
            .overlay(shape.stroke(edge.color, lineWidth: edge.width))
            .overlay(alignment: .topLeading) {
                if let pane, page.floats(pane) {
                    Image(systemName: "pip").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let pane, pane.plugin != nil || page.shownChat(pane) != nil {
                    // A tile makes no web view, proxy or transcript read, and takes no web view from its card, which
                    // then draws blank as it goes back.
                    if let picture = pane.terminalID.flatMap(page.terminals.picture) {
                        scaled(CardPicture(picture: picture, pane: pane)
                            .miniCard(pane.id, pane.plugin.map { $0.manifest?.id ?? $0.plugin } ?? "chat"), content,
                            under: header)
                    } else {
                        Image(symbol: pane.plugin != nil ? pane.iconID : "bubble.left.and.bubble.right")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .miniCard(pane.id, "symbol")
                    }
                } else if let pane, let id = pane.terminalID {
                    let isLive = live.contains(id)
                    let view = isLive ? page.terminal(pane) : page.terminals.terminals([id]).first
                    let drawsLive = isLive && view?.snapshot == nil
                    ZStack {
                        Color.clear
                        if drawsLive, let view {
                            MiniTerminal(terminal: view, size: terminal)
                        } else if let snapshot = view?.snapshot {
                            Snapshot(surface: snapshot)
                        }
                    }
                    .miniCard(pane.id, "\(view?.pictured != true ? "loading" : drawsLive ? "live" : "snapshot") "
                        + "\(view?.snapshot?.width ?? 0)")
                    .frame(width: terminal.width * scale, height: terminal.height * scale)
                    .padding(.leading, PaneCard.inset * scale)
                    .padding(.top, header * scale)
                }
            }
    }

    private func scaled(_ view: some View, _ content: CGSize, under header: CGFloat) -> some View {
        view.frame(width: content.width, height: content.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: content.width * scale, height: content.height * scale, alignment: .topLeading)
            .disabled(true)
            .allowsHitTesting(false)
            .padding(.top, header * scale)
    }
}

private extension View {
    /// A group's value does not reach XCUITest; static text's does.
    func miniCard(_ paneID: String, _ value: String) -> some View {
        readableText(value).accessibilityIdentifier("overview.card.\(paneID)")
    }
}

private struct Snapshot: NSViewRepresentable {
    let surface: IOSurface

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resize
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        view.layer?.contents = surface
    }
}

/// Its bounds are the card's terminal size, so AppKit scales the layer and libghostty keeps its grid (herdr's PTY never
/// resizes).
struct MiniTerminal: NSViewRepresentable {
    let terminal: PaneTerminal
    let size: CGSize

    func makeNSView(context _: Context) -> Mini {
        let mini = Mini()
        mini.lender = terminal.view.superview
        mini.size = size
        mini.wantsLayer = true
        mini.clipsToBounds = true
        mini.addSubview(terminal.view)
        return mini
    }

    func updateNSView(_ mini: Mini, context _: Context) {
        mini.size = size
        mini.fit()
    }

    static func dismantleNSView(_ mini: Mini, coordinator _: ()) {
        if let view = mini.subviews.first, let lender = mini.lender, lender.window != nil {
            lender.addSubview(view)
        }
    }

    final class Mini: NSView {
        var size = CGSize.zero
        weak var lender: NSView?
        private var fitting: Task<Void, Never>?

        override var isFlipped: Bool {
            true
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            fit()
        }

        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            fitting?.cancel()
            fit(now: true)
        }

        func fit(now: Bool = false) {
            guard !frame.isEmpty, size.width > 0, size.height > 0 else { return }
            setBoundsSize(size)
            fitting?.cancel()
            guard let view = subviews.first as? PaneSurfaceView, view.frame.size != size else { return }
            guard now || view.terminal?.grid == nil || view.frame.isEmpty else {
                return SettlingHost.settle(&fitting) { [weak self] in self?.fit(now: true) }
            }
            SettlingHost.place(view, CGRect(origin: .zero, size: size))
        }
    }
}
