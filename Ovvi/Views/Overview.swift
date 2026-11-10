import AppKit
import Carbon.HIToolbox
import HerdrKit
import SwiftUI

struct Overview: View {
    let pages: WindowPages
    let leading: CGFloat
    @State private var monitor: Any?

    var body: some View {
        GeometryReader { proxy in
            let side = max(48, proxy.size.width * 0.08)
            if let page = pages.current {
                OverviewPage(
                    pages: pages,
                    page: page,
                    size: CGSize(width: max(proxy.size.width - leading - 2 * gap, 1),
                                 height: max(proxy.size.height - 4 - gap, 1)),
                    side: side,
                    columns: min(4, max(2, Int((proxy.size.width - 2 * side + 16) / 356))),
                ) { workspace, tab in
                    page.select(workspace, tab: tab.id)
                    pages.closeOverview()
                }
                .equatable()
                // A view of its own per session: herdr's tab ids repeat across sessions.
                .id(page.id)
            }
        }
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
                    pages.closeOverview()
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
}

extension View {
    /// Laid out while the overview is open, hidden, so it shows at once when it closes: made then, it comes a moment
    /// late in a big session.
    func underOverview(_ pages: WindowPages, own: Bool = false) -> some View {
        let shown = pages.overview == own
        return opacity(shown ? 1 : 0)
            .animation(nil, value: shown)
            .allowsHitTesting(shown)
            // Not `accessibilityHidden(false)`, which overrides the hidden ones inside.
            .accessibilityElement(children: shown ? .contain : .ignore)
            // Out of the key view loop too: Tab would reach a hidden field.
            .disabled(!shown)
    }
}
