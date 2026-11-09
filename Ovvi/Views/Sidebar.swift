import HerdrKit
import SwiftUI

/// Arc-style pages, one per session open in the window (D43), paged sideways; under them the page dots, the machine's
/// Archived Sessions, the filter and Open Session. Each page lists its session's spaces like herdr's Spaces panel, each
/// unfolding to its agents (ui/window#sidebar).
struct Sidebar: View {
    static let widths: ClosedRange<Double> = 227 ... 480
    /// Rex's rows: 10 pt in from the window's edge.
    static let rowInsets = EdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 3)

    let pages: WindowPages
    @Binding var width: Double
    let openSession: () -> Void
    @State private var filter = ""
    @State private var swipe = Swipe()
    private var settings = AppSettings()
    /// The pages' frame in the window, for the router.
    @State private var area = CGRect.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            pagesAndFooter
                // On the window background, as in the reference: only the pane cards are lighter.
                .frame(width: width - gap)
            ResizeHandle(width: $width)
        }
        .foregroundStyle(look.chrome)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar")
        // The window's open sessions in page order, as the Window menu's ⌥⌘1–9 go.
        .testValue("sidebar.sessions", "Sessions", pages.list.map(\.id).joined(separator: " "))
        // e2e: made when it shows, not when the overview closes.
        .onAppear { Latency.shared.note("sidebar made") }
    }

    private var pagesAndFooter: some View {
        VStack(spacing: 0) {
            Pager(swipe: swipe, width: width - gap) {
                HStack(spacing: 0) {
                    // At rest only the page in view (`Pager`): the others would lie over the tab's page, in the
                    // sidebar's accessibility frame (which takes in laid-out views past the clip) and in AppKit's
                    // hit tests.
                    ForEach(swipe.moving ? pages.list : pages.list.filter { $0 === pages.current }) { page in
                        SidebarPage(page: page, pages: pages, filter: filter)
                            .frame(width: width - gap)
                            .accessibilityHidden(page !== pages.current)
                            .allowsHitTesting(page === pages.current)
                            .transition(.identity)
                    }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { area = $0 }
            // Not under the overview, which hides it.
            .background(PagesAnchor(
                step: step,
                drag: pages.overview ? nil : drag as (Double, Bool) -> Void,
                lift: lift,
                area: area,
            ))
            // A key, a new page or the sheet: slide there with the session spring. A swipe is there already.
            // Under the overview at once: hidden, it would draw both pages for 0.3 s.
            .onChange(of: pages.list.map(\.id) + [pages.current?.id ?? ""], initial: true) { old, new in
                guard let index = pages.list.firstIndex(where: { $0 === pages.current }),
                      swipe.slide != Double(index) else { return }
                let slides = old.last != new.last && !pages.overview && !(reduceMotion && !Animation.forceMotion)
                slide(to: index, with: slides ? .session() : nil)
            }
            if pages.list.count > 1 {
                PageDots(pages: pages)
            }
            // The machine's, the same on every page: it stays while the pages slide.
            if settings.showClosed, let page = pages.current {
                ArchivedShelf(page: page)
                    .padding(.leading, Sidebar.rowInsets.leading).padding(.trailing, Sidebar.rowInsets.trailing)
                    .padding(.top, 4)
            }
            HStack(spacing: 2) {
                FilterField(prompt: "Filter", text: $filter, identifier: "sidebar.filter")
                    .onExitCommand { filter = "" }
                    .padding(.trailing, 4)
                IconButton(symbol: "plus.square.on.square", help: "Open Session", key: .openSession,
                           action: openSession)
                    .accessibilityIdentifier("sidebar.open-session")
            }
            .padding(Sidebar.rowInsets)
            .padding(.top, 8)
        }
    }
}

private struct PageDots: View {
    let pages: WindowPages

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pages.list) { page in
                Button { pages.show(page) } label: {
                    Circle().fill(page === pages.current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: 6, height: 6)
                        // The gap is part of each dot's click area.
                        .frame(width: 12, height: 12)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Detach Session") { pages.close(page) }.disabled(pages.list.count < 2) }
                .accessibilityLabel(page.store.title)
                .accessibilityIdentifier("sidebar.dot.\(page.id)")
                .accessibilityAddTraits(page === pages.current ? .isSelected : [])
            }
        }
        .padding(.top, 4)
    }
}

/// The handle at the sidebar's trailing edge, over the tab page's 8 pt gap: a drag resizes it in `Sidebar.widths`.
private struct ResizeHandle: View {
    @Binding var width: Double
    @State private var start: Double?

    var body: some View {
        Color.clear.frame(width: gap).contentShape(.rect)
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { drag in
                let start = start ?? width
                self.start = start
                resize(to: start + drag.translation.width)
            }.onEnded { _ in start = nil })
            .accessibilityElement()
            .accessibilityLabel("Sidebar Width")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { resize(to: width + ($0 == .increment ? 20 : -20)) }
            .accessibilityIdentifier("sidebar.resize")
    }

    private func resize(to value: Double) {
        width = min(max(value, Sidebar.widths.lowerBound), Sidebar.widths.upperBound)
    }
}

extension Sidebar {
    /// The router's moves of a sideways swipe (in points, toward later pages): the pages follow the fingers from
    /// where they are drawn (a slide stops), and stop at the first and last page. Not under a panel (the palette,
    /// Open Session), which would then act on another page.
    private func drag(_ delta: Double, first: Bool) {
        guard !pages.panelOpen else { return }
        let width = max(width - gap, 1), last = Double(max(pages.list.count - 1, 0))
        if first {
            swipe.moves += 1
            // Mid-slide: from where the pages are drawn.
            if swipe.moving {
                swipe.slide = swipe.drawn / width
            }
            swipe.moving = true
        }
        swipe.slide = min(max(swipe.slide + delta / width, 0), last)
    }

    /// A mouse's sideways wheel: the next or previous page.
    private func step(_ offset: Int) {
        if !pages.panelOpen {
            pages.step(offset)
        }
    }

    /// A swipe's lift, with the fingers' speed in points a second: the pages slide on from that speed to the next
    /// page that way, or to the nearest one when slow, with the session spring; the window shows that session as
    /// the pages arrive. The pages are the app's own: a scroll view's paging snap took about 0.4 s, and on a quick
    /// flick stood still until a timeout, then snapped back while the window showed the other session.
    private func lift(_ speed: Double) {
        let width = max(width - gap, 1), page = swipe.slide
        let index = Swipe.landing(page, speed: speed, count: pages.list.count)
        guard pages.list.indices.contains(index) else { return }
        let target = pages.list[index]
        Latency.shared.lifted(page * width)
        // Shown once the pages arrive; shown at the lift, the session held the slide's first frames.
        let still = reduceMotion && !Animation.forceMotion
        slide(to: index, with: still ? nil : .session(speed: speed / width, distance: Double(index) - page)) {
            if target !== pages.current {
                Latency.shared.shown()
                pages.show(target)
            }
        }
    }

    /// The pages slide to the page at `index` (or go, with no animation); `then` runs as they arrive, unless
    /// another move took them meanwhile.
    private func slide(to index: Int, with animation: Animation?, then: @escaping () -> Void = {}) {
        swipe.moves += 1
        let move = swipe.moves
        // No move (a flick at the first or last page), no animation: it might never end.
        guard let animation, swipe.slide != Double(index) else {
            swipe.slide = Double(index)
            swipe.moving = false
            then()
            return
        }
        let slide = {
            withAnimation(animation, completionCriteria: .logicallyComplete) {
                swipe.slide = Double(index)
            } completion: {
                if swipe.moves == move {
                    swipe.moving = false
                    then()
                }
            }
        }
        guard swipe.moving else {
            // The other pages first, in an update of their own: in the slide's, their offset from rest would too.
            swipe.moving = true
            Task {
                if swipe.moves == move {
                    slide()
                }
            }
            return
        }
        slide()
    }
}
