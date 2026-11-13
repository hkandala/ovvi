import HerdrKit
import SwiftUI

struct Sidebar: View {
    static let widths: ClosedRange<Double> = 227 ... 480
    static let rowInsets = EdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 3)

    let pages: WindowPages
    @Binding var width: Double
    let openSession: () -> Void
    @State private var filter = ""
    @State private var swipe = Swipe()
    private var settings = AppSettings()
    @State private var area = CGRect.zero
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            pagesAndFooter
                .frame(width: width - gap)
            ResizeHandle(width: $width)
        }
        .foregroundStyle(look.chrome)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar")
        .testValue("sidebar.sessions", "Sessions", pages.list.map(\.id).joined(separator: " "))
        .onAppear { Latency.shared.note("sidebar made") }
    }

    private var pagesAndFooter: some View {
        VStack(spacing: 0) {
            Pager(swipe: swipe, width: width - gap) {
                HStack(spacing: 0) {
                    // At rest only the page in view: the others would lie over the tab's page, in the sidebar's
                    // accessibility frame (which takes in laid-out views past the clip) and in AppKit's hit tests.
                    ForEach(swipe.moving ? pages.list : pages.list.filter { $0 === pages.current }) { page in
                        SidebarPage(page: page, pages: pages, filter: filter,
                                    bottom: pages.list.count > 1 ? PageDots.height : 0, openSession: openSession)
                            .frame(width: width - gap)
                            .accessibilityHidden(page !== pages.current)
                            .allowsHitTesting(page === pages.current)
                            .transition(.identity)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if pages.list.count > 1 {
                    PageDots(pages: pages)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { area = $0 }
            .background(PagesAnchor(
                step: step,
                drag: pages.overview ? nil : drag as (Double, Bool) -> Void,
                lift: lift,
                area: area,
            ))
            // Under the overview at once: hidden, it would draw both pages for 0.3 s.
            .onChange(of: pages.list.map(\.id) + [pages.current?.id ?? ""], initial: true) { old, new in
                guard let index = pages.list.firstIndex(where: { $0 === pages.current }),
                      swipe.slide != Double(index) else { return }
                let slides = old.last != new.last && !pages.overview && !Animation.reduced
                slide(to: index, with: slides ? .session() : nil)
            }
            if settings.showArchived, let page = pages.current {
                ArchivedShelf(pages: pages, page: page)
                    .padding(.leading, Sidebar.rowInsets.leading).padding(.trailing, Sidebar.rowInsets.trailing)
                    .padding(.top, 2)
            }
            HStack(spacing: 2) {
                FilterField(prompt: "Filter", text: $filter, identifier: "sidebar.filter")
                    .onExitCommand { filter = "" }
                    .padding(.trailing, 4)
                IconButton(symbol: "plus.square.on.square", help: "Open Session", key: .hotkey("session.open"),
                           action: openSession)
                    .accessibilityIdentifier("sidebar.open-session")
            }
            .padding(Sidebar.rowInsets)
            .padding(.top, 8)
        }
    }
}

private struct PageDots: View {
    static let height: CGFloat = 18
    let pages: WindowPages

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pages.list) { page in
                Button { pages.show(page) } label: {
                    Circle().fill(page === pages.current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: 6, height: 6)
                        .frame(width: 12, height: 12)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Detach Session") { pages.close(page) }.disabled(!pages.canDetach) }
                .accessibilityLabel(page.store.title)
                .accessibilityIdentifier("sidebar.dot.\(page.id)")
                .accessibilityAddTraits(page === pages.current ? .isSelected : [])
            }
        }
        .padding(.leading, Sidebar.rowInsets.leading).padding(.trailing, Sidebar.rowInsets.trailing)
        .padding(.bottom, 6)
    }
}

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
    /// Not under a panel (the palette, Open Session), which would then act on another page.
    private func drag(_ delta: Double, first: Bool) {
        guard !pages.panelOpen else { return }
        let width = max(width - gap, 1), last = Double(max(pages.list.count - 1, 0))
        if first {
            swipe.moves += 1
            if swipe.moving {
                swipe.slide = swipe.drawn / width
            }
            swipe.moving = true
        }
        swipe.slide = min(max(swipe.slide + delta / width, 0), last)
    }

    private func step(_ offset: Int) {
        if !pages.panelOpen {
            pages.step(offset)
        }
    }

    /// The pages are the app's own: a scroll view's paging snap takes about 0.4 s, and a quick flick stands still until
    /// a timeout, then snaps back.
    private func lift(_ speed: Double) {
        let width = max(width - gap, 1), page = swipe.slide
        let index = Swipe.landing(page, speed: speed, count: pages.list.count)
        guard pages.list.indices.contains(index) else { return }
        let target = pages.list[index]
        Latency.shared.lifted(page * width)
        // Shown once the pages arrive: shown at the lift, the session holds the slide's first frames.
        slide(
            to: index,
            with: Animation.reduced ? nil : .session(speed: speed / width, distance: Double(index) - page),
        ) {
            if target !== pages.current {
                Latency.shared.shown()
                pages.show(target)
            }
        }
    }

    private func slide(to index: Int, with animation: Animation?, then: @escaping () -> Void = {}) {
        swipe.moves += 1
        let move = swipe.moves
        // No move, no animation: it might never end.
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
            // The other pages first, in an update of their own: in the slide's, their offset from rest would animate
            // too.
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
