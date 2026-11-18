import HerdrKit
import SwiftUI

struct Sidebar: View {
    static let widths: ClosedRange<Double> = 244 ... 480
    static let rowInsets = EdgeInsets(top: 0, leading: 10, bottom: 8, trailing: 3)

    let pages: WindowPages
    @Binding var width: Double
    @Binding var panel: WindowPanel?
    @State private var filter = ""
    @State private var swipe = Swipe()
    @State private var area = CGRect.zero
    @AppStorage(Page.foldsAndShelves, store: .sidebar) private var opened = ""
    /// The user opened the agents section, so the keys go to it.
    @State private var opening = false
    /// The defaults' open line, followed in a transaction of its own: a write to the defaults draws with none.
    @State private var agentsOpen: Bool
    @Environment(\.look) private var look

    init(pages: WindowPages, width: Binding<Double>, panel: Binding<WindowPanel?>) {
        (self.pages, _width, _panel) = (pages, width, panel)
        // Shown again, the sidebar draws its first frame with the section.
        _agentsOpen = State(initialValue: (UserDefaults.sidebar.string(forKey: Page.foldsAndShelves) ?? "")
            .hasLine(pages.agentsKey))
    }

    var body: some View {
        HStack(spacing: 0) {
            headerAndPages
                .frame(width: width - gap)
            ResizeHandle(width: $width)
        }
        .foregroundStyle(look.chrome)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar")
        .testValue("sidebar.sessions", "Sessions", pages.list.map(\.id).joined(separator: " "))
        .onAppear { Latency.shared.note("sidebar made") }
    }

    private var headerAndPages: some View {
        VStack(spacing: 0) {
            if let page = pages.current {
                SessionHeader(pages: pages, page: page, openSession: openSession)
                    .padding(.leading, Sidebar.rowInsets.leading).padding(.trailing, Sidebar.rowInsets.trailing)
            }
            FilterField(prompt: "Find a space or agent", text: $filter, identifier: "sidebar.filter",
                        symbol: "magnifyingglass")
                .onExitCommand { filter = "" }
                .padding(.leading, Sidebar.rowInsets.leading).padding(.trailing, Sidebar.rowInsets.trailing)
                .padding(.top, 8).padding(.bottom, 10)
            Pager(swipe: swipe, width: width - gap) {
                HStack(spacing: 0) {
                    // At rest only the page in view: the others would lie over the tab's page, in the sidebar's
                    // accessibility frame (which takes in laid-out views past the clip) and in AppKit's hit tests.
                    ForEach(swipe.moving ? pages.list : pages.list.filter { $0 === pages.current }) { page in
                        SidebarPage(page: page, pages: pages, filter: filter, openSession: openSession)
                            .frame(width: width - gap)
                            .accessibilityHidden(page !== pages.current)
                            .allowsHitTesting(page === pages.current)
                            .transition(.identity)
                    }
                }
            }
            // Under the overview at once: hidden, it would draw both pages for 0.3 s.
            .onChange(of: pages.list.map(\.id) + [pages.current?.id ?? ""], initial: true) { old, new in
                guard let index = pages.list.firstIndex(where: { $0 === pages.current }),
                      swipe.slide != Double(index) else { return }
                let slides = old.last != new.last && !pages.overview && !Animation.reduced
                slide(to: index, with: slides ? .session() : nil)
            }
            // A band of their own: over the list, rows scrolled under them would show through.
            if pages.list.count > 1 {
                PageDots(pages: pages)
            }
            // Slides up from behind the foot as it fades in, as the session shelf slides down.
            VStack(spacing: 0) {
                if let page = pages.current, agentsOpen {
                    AgentsSection(pages: pages, page: page, focuses: opening, close: toggleAgents)
                        .padding(.leading, Sidebar.rowInsets.leading).padding(.trailing, Sidebar.rowInsets.trailing)
                        // Its border a row gap under the list's cut rows; the dots' band keeps them away already.
                        .padding(.top, pages.list.count < 2 ? WorkspaceRow.gap : 2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Empty, it would have no width either, and the section would grow out of its middle.
            .frame(maxWidth: .infinity)
            .clipped()
            // Its lists take their full height before the spaces' list takes the rest.
            .layoutPriority(1)
            SidebarFoot(pages: pages, panel: $panel, open: agentsOpen, toggle: toggleAgents)
                .padding(.leading, Sidebar.rowInsets.leading).padding(.trailing, Sidebar.rowInsets.trailing)
        }
        .onChange(of: opened.hasLine(pages.agentsKey)) { _, open in withAnimation(.slide) { agentsOpen = open } }
        // The whole sidebar swipes its pages, the header and the filter too.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { area = $0 }
        .background(PagesAnchor(
            step: step,
            drag: pages.overview ? nil : drag as (Double, Bool) -> Void,
            lift: lift,
            area: area,
        ))
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
    private func openSession() {
        panel = .openSession
    }

    private func toggleAgents() {
        opening = !opened.hasLine(pages.agentsKey)
        opened = opened.togglingLine(pages.agentsKey)
        if !opening {
            pages.current?.focusKeyboardCard()
        }
    }

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
