import AppKit
import SwiftUI

/// The registry owns the view and a host takes it (`adopt`), so that a page SwiftUI makes again never destroys the
/// surface.
struct TerminalHost: NSViewRepresentable {
    let terminal: PaneTerminal
    /// On the host view: SwiftUI's `opacity` moves the terminal's accessibility frame half a card down, so that clicks
    /// at its center miss it.
    let alpha: CGFloat
    /// An input, not read from the environment in `updateNSView`, which SwiftUI does not call for an environment
    /// change alone.
    let hidden: Bool

    func makeNSView(context _: Context) -> SettlingHost {
        let host = SettlingHost()
        host.clipsToBounds = true
        adopt(host)
        if SettlingHost.record {
            host.setAccessibilityElement(true)
            host.setAccessibilityRole(.group)
        }
        return host
    }

    func updateNSView(_ host: SettlingHost, context _: Context) {
        // Only as its kept page comes into view: at every update, a card that leaves (the main window's, as its pane
        // floats) would take the view from the shown one.
        if host.isHidden, !hidden {
            adopt(host)
        }
        host.hide(hidden)
        if host.alphaValue == 0, alpha > 0,
           !Animation.reduced
        {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                host.animator().alphaValue = alpha
            }
        } else {
            host.alphaValue = alpha
        }
        if SettlingHost.record {
            host.setAccessibilityIdentifier("host.\(terminal.paneID)")
        }
    }

    /// A shown host takes the view; a hidden one only a view no host has, and takes it as it shows (`updateNSView`). A
    /// moved pane's old page, out of view, can make a host after the new card's, and must not take the view from it.
    private func adopt(_ host: SettlingHost) {
        guard terminal.view.superview !== host, !hidden || terminal.view.superview == nil else { return }
        host.addSubview(terminal.view)
        host.fit()
    }
}

struct TerminalCard: View {
    let terminal: PaneTerminal
    let watched: Bool
    let alpha: CGFloat
    @Environment(\.pageHidden) private var hidden
    @Environment(\.look) private var look
    @Environment(\.litCard) private var lit

    var body: some View {
        TerminalHost(terminal: terminal, alpha: alpha, hidden: hidden)
            // A new terminal in the same spot (panes swapped) needs a new host to adopt it.
            .id(ObjectIdentifier(terminal))
            .overlay(alignment: .bottom) {
                switch terminal.state {
                case _ where alpha == 0: EmptyView()
                case .watching where !watched:
                    Button("In use elsewhere · Take Back", action: terminal.takeBack)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("pane.\(terminal.paneID).take-back")
                        .padding(gap)
                // While the page reconnects, its overlay says why.
                case let .failed(text) where terminal.live:
                    EmptyState(symbol: "terminal", title: "The terminal stopped", text: text, compact: true) {
                        Button("Retry", action: terminal.retry).buttonStyle(.glassProminent)
                            .accessibilityIdentifier("pane.\(terminal.paneID).retry")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(look.cardSolid(keyboard: lit))
                case .idle, .live, .watching, .failed:
                    EmptyView()
                }
            }
            .overlay {
                // A click on the spinner is the card's: it takes the keyboard while the card loads.
                if !terminal.ready, !terminal.state.isFailed, alpha > 0 {
                    Loader(delay: .milliseconds(500)).allowsHitTesting(false)
                }
            }
    }
}

struct TerminalItems: View {
    let view: PaneSurfaceView

    var body: some View {
        edit("Copy", #selector(NSText.copy(_:)))
        edit("Paste", #selector(NSText.paste(_:)))
        edit("Select All", #selector(NSText.selectAll(_:)))
        Divider()
    }

    private func edit(_ title: String, _ action: Selector) -> some View {
        Button(title) { NSApp.sendAction(action, to: view, from: nil) }
    }
}
