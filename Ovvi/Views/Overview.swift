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
                        // Pictures only: a live terminal stays in its tile until the page takes it.
                        Zoom(from: zoom.from, page: tabPage) {
                            // Not an overview opened again since a second leave closed this one.
                            if pages.leaving {
                                pages.closeOverview()
                            }
                        } content: {
                            Miniature(tab: zoom.tab, page: page, size: tabPage.size, live: [])
                        }
                        .frame(width: tabPage.width, height: tabPage.height)
                        .padding(.leading, tabPage.minX)
                        .padding(.top, tabPage.minY)
                        .accessibilityHidden(true)
                    }
                }
                .onChange(of: pages.leaving, initial: true) {
                    if pages.leaving, zoom == nil {
                        leave(page)
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
    private func leave(_ page: Page) {
        guard let tab = page.selectedTab, pages.overviewTabs[page.id]?.contains(tab.id) == true,
              let from = pages.tileFrames["\(page.id) \(tab.id)"] else { return pages.closeOverview() }
        // A tile that still streams has no picture yet for the zoom to grow.
        pages.terminals.takePictures(of: pages.tileCards(page, tab.id).map(\.0))
        zoom = (tab, from)
        // The other tiles' fade. Next turn: a view inserted in the same update as the change starts at its end.
        Task {
            withAnimation(.motion(.easeOut(duration: WindowPages.zoom))) { grown = true }
        }
    }
}

/// Grown by Core Animation, as cards move (`CardMotion`): the render server draws its frames, so work on the main
/// thread meanwhile drops none (an accessibility client's snapshot of the window, 75 ms in the VM and 380 ms on CI,
/// left one frame of a zoom drawn on the main thread). The content lays out once, at the page's size.
private struct Zoom<Content: View>: NSViewRepresentable {
    let from: CGRect
    let page: CGRect
    let done: () -> Void
    @ViewBuilder let content: Content

    func makeNSView(context _: Context) -> NSHostingView<Content> {
        let host = NSHostingView(rootView: content)
        host.safeAreaRegions = []
        host.wantsLayer = true
        guard let layer = host.layer, page.width > 0, page.height > 0 else {
            done()
            return host
        }
        // The layer's y grows upward, as its superlayer's (`MovingCard`): the tile's rect in it, then scaled about the
        // anchor.
        let scale = CGSize(width: from.width / page.width, height: from.height / page.height)
        let anchor = CGPoint(x: layer.anchorPoint.x * page.width, y: layer.anchorPoint.y * page.height)
        let start = CATransform3DConcat(
            CATransform3DMakeScale(scale.width, scale.height, 1),
            CATransform3DMakeTranslation(from.minX - page.minX + (scale.width - 1) * anchor.x,
                                         page.maxY - from.maxY + (scale.height - 1) * anchor.y, 0),
        )
        let grow = CABasicAnimation(keyPath: "transform")
        (grow.fromValue, grow.toValue, grow.duration) = (start, CATransform3DIdentity, WindowPages.zoom)
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock(done)
        layer.add(grow, forKey: "zoom")
        CATransaction.commit()
        if SettlingHost.record {
            WindowPages.zooms += 1
        }
        return host
    }

    func updateNSView(_ host: NSHostingView<Content>, context _: Context) {
        host.rootView = content
    }
}

extension View {
    /// Laid out while the overview is open, hidden, so it shows at once when it closes: made then, it comes a moment
    /// late in a big session.
    func underOverview(_ pages: WindowPages, own: Bool = false) -> some View {
        let shown = (pages.overview && !pages.leaving) == own
        // Fades with the tile's zoom; the opacity alone: the tab the tile picks changes in the same update.
        return animation(pages.leaving ? .motion(.easeOut(duration: 0.12)) : nil) { $0.opacity(shown ? 1 : 0) }
            .allowsHitTesting(shown)
            // Not `accessibilityHidden(false)`, which overrides the hidden ones inside.
            .accessibilityElement(children: shown ? .contain : .ignore)
            // Out of the key view loop too: Tab would reach a hidden field.
            .disabled(!shown)
    }
}
