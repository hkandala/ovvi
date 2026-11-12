import AppKit
import Carbon.HIToolbox
import HerdrKit
import SwiftUI

struct Overview: View {
    let pages: WindowPages
    let leading: CGFloat
    @State private var monitor: Any?
    @State private var zoom: (tab: HostStore.Tab, from: CGRect)?
    @State private var grown = false

    nonisolated static let space = "overview"

    var body: some View {
        GeometryReader { proxy in
            let side = max(48, proxy.size.width * 0.08)
            // The tab's page, as `TabPage` lays it out beside the sidebar.
            let tabPage = CGRect(x: leading + gap, y: 4, width: max(proxy.size.width - leading - 2 * gap, 1),
                                 height: max(proxy.size.height - 4 - gap, 1))
            if let page = pages.current {
                OverviewPage(
                    pages: pages,
                    page: page,
                    size: tabPage.size,
                    side: side,
                    columns: min(4, max(2, Int((proxy.size.width - 2 * side + 16) / 356))),
                ) { workspace, tab in
                    page.select(workspace, tab: tab.id)
                    pages.leaveOverview()
                }
                .equatable()
                // A view of its own per session: herdr's tab ids repeat across sessions.
                .id(page.id)
                .opacity(grown ? 0 : 1)
                .shielded(zoom != nil)
                .overlay(alignment: .topLeading) {
                    if let zoom {
                        Miniature(tab: zoom.tab, page: page, size: tabPage.size, live: pages.overviewLive)
                            .modifier(Grow(progress: grown ? 1 : 0, from: zoom.from, page: tabPage))
                    }
                }
                .onChange(of: pages.leaving) {
                    if pages.leaving, zoom == nil {
                        leave(page, in: CGRect(origin: .zero, size: proxy.size))
                    }
                }
            }
        }
        .coordinateSpace(.named(Self.space))
        .testValue("overview.snapshots", "Overview Snapshots",
                   "\(pages.overviewLive.count) \(PaneTerminal.snapshots.count)", shown: SettlingHost.record)
        // Esc by a monitor: a SwiftUI focus does not take the keyboard from a terminal moving into a miniature.
        .onAppear {
            pages.window?.makeFirstResponder(nil)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard Int(event.keyCode) == kVK_Escape else { return event }
                let leave = MainActor.assumeIsolated {
                    guard let window = pages.window, NSApp.keyWindow === window, !pages.panelOpen,
                          !(window.firstResponder is NSText) else { return false }
                    pages.leaveOverview()
                    return true
                }
                return leave ? nil : event
            }
        }
        .onDisappear {
            monitor.map(NSEvent.removeMonitor)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview")
    }

    /// At once when the tab's tile is out of view.
    private func leave(_ page: Page, in view: CGRect) {
        guard let tab = page.selectedTab, let from = pages.tileFrames["\(page.id) \(tab.id)"], from.intersects(view)
        else { return pages.closeOverview() }
        zoom = (tab, from)
        // Next turn: a view inserted in the same update as the change starts at its end, with no motion.
        Task {
            withAnimation(.easeOut(duration: 0.18)) { grown = true } completion: {
                pages.closeOverview()
            }
        }
    }
}

/// The zoom's frame at each step: a plain animated frame reaches the miniature's layout only at its end.
private struct Grow: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGRect
    let page: CGRect

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        if SettlingHost.record, progress > 0, progress < 1 {
            WindowPages.zoomSteps += 1
        }
        let step = { (start: CGFloat, end: CGFloat) in start + (end - start) * progress }
        let rect = CGRect(x: step(from.minX, page.minX), y: step(from.minY, page.minY),
                          width: step(from.width, page.width), height: step(from.height, page.height))
        return content.frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
    }
}

extension View {
    /// Laid out while the overview is open, hidden, so it shows at once when it closes: made then, it comes a moment
    /// late in a big session.
    func underOverview(_ pages: WindowPages, own: Bool = false) -> some View {
        let shown = (pages.overview && !pages.leaving) == own
        // Fades with the tile's zoom; the opacity alone: the tab the tile picks changes in the same update.
        return animation(pages.leaving ? .easeOut(duration: 0.12) : nil) { $0.opacity(shown ? 1 : 0) }
            .allowsHitTesting(shown)
            // Not `accessibilityHidden(false)`, which overrides the hidden ones inside.
            .accessibilityElement(children: shown ? .contain : .ignore)
            // Out of the key view loop too: Tab would reach a hidden field.
            .disabled(!shown)
    }
}
