import HerdrKit
import SwiftUI
import WebKit

extension Page {
    /// A browser pane's card, made on first use.
    func browser(_ pane: HostStore.Pane) -> Browser? {
        guard let terminalID = pane.terminalID, let label = pane.browser else { return nil }
        return terminals.browser(pane, label, terminalID: terminalID, store: store)
    }

    /// A browser pane's page: its title, else its host, else its address; nil before it has one. Builds no card:
    /// menus ask for every tab's title.
    func browserTitle(_ pane: HostStore.Pane, _ label: PaneLabel) -> String? {
        let browser = pane.terminalID.flatMap(terminals.built)
        let address = browser?.address ?? label.arg
        return browser.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? URL(string: address)?.host
            ?? (address.isEmpty ? nil : address)
    }
}

extension CommandList {
    /// A browser card's (ui/browser#commands-on-a-browser-card), in the main and the floating windows. Open Location
    /// edits a new pane's folder line too (ui/new-pane#the-folder).
    static func browser(_ browser: Browser?, chooser: Chooser?) -> [Command] {
        [
            Command(section: .view, title: "Reload Page", key: .init("r"), symbol: "arrow.clockwise",
                    keywords: "refresh browser", enabled: browser?.loaded == true) { browser?.reload() },
            Command(section: .edit, title: "Open Location", key: .init("l"), symbol: "link",
                    keywords: "address url browser folder", enabled: browser != nil || chooser != nil,
                    action: {
                        browser?.wantsAddress = true
                        chooser?.editing = true
                    }),
            Command(section: .edit, title: "Show Web Inspector", key: .init("i", modifiers: [.command, .option]),
                    symbol: "hammer", keywords: "developer tools devtools browser",
                    enabled: browser?.loaded == true) { browser?.view.showInspector() },
        ]
    }
}

/// The card's page (ui/browser#the-card).
struct BrowserCard: View {
    let browser: Browser
    let page: Page
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageHidden) private var hidden

    var body: some View {
        let shows = browser.ready && browser.failure == nil && browser.asking == nil && browser.loaded
        // A network switch makes a new web view.
        WebHost(view: browser.view, hidden: hidden).id(ObjectIdentifier(browser.view))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding([.horizontal, .bottom], 6)
            .opacity(shows ? 1 : 0)
            .overlay(alignment: .top) {
                if browser.loading {
                    ProgressView(value: browser.progress).progressViewStyle(.linear).tint(.accentColor)
                        .frame(height: 2).scaleEffect(y: 0.5)
                }
            }
            // A click anywhere on the empty, error or loading card makes it the keyboard card, as one on a page
            // does: the hidden web view takes no click.
            .overlay {
                if !shows {
                    // Also on its buttons (Reload, Open).
                    cover.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(.rect)
                        .simultaneousGesture(TapGesture().onEnded {
                            page.tookKeyboard(browser.terminalID)
                            browser.takeKeyboard()
                        })
                }
            }
            .overlay {
                if let popup = browser.popup {
                    Popup(view: popup.view, title: popup.host, close: browser.closePopup).padding(24)
                }
            }
            // No fade over a picture: half way, both showed the card's fill through.
            .animation(reduceMotion && !Animation.forceMotion || browser.view.shot.image != nil ? nil
                : .easeOut(duration: 0.15), value: browser.ready)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("browser.\(browser.paneID).card")
    }

    @ViewBuilder private var cover: some View {
        if let failure = browser.failure {
            failed(failure.text, hint: failure.hint)
        } else if let url = browser.asking {
            Asking(browser: browser, url: url)
        } else if !browser.ready {
            // A card made again (its old one dropped, ui/browser): its last picture until its page drew.
            if let picture = browser.view.shot.image, let pane = browser.store?.pane(browser.paneID) {
                CardPicture(picture: picture, pane: pane)
            } else {
                PluginLoader(plugin: Registry.browser)
            }
        } else {
            Image(systemName: "globe").font(.system(size: 44, weight: .light)).foregroundStyle(.tertiary)
                .accessibilityIdentifier("browser.\(browser.paneID).empty")
        }
    }

    private func failed(_ text: String, hint: String?) -> some View {
        EmptyState(
            symbol: "exclamationmark.triangle",
            title: text,
            text: hint,
            id: "browser.\(browser.paneID).message",
        ) {
            Button("Reload", action: browser.reload).buttonStyle(.glassProminent)
                .accessibilityIdentifier("browser.\(browser.paneID).retry")
        }
    }
}

/// "Open this page?" (ui/browser#when-a-page-loads-by-itself).
private struct Asking: View {
    let browser: Browser
    let url: URL

    var body: some View {
        let id = "browser.\(browser.paneID)"
        VStack(spacing: 10) {
            Image(systemName: "globe").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
            Text("Open this page?").font(.system(size: 15, weight: .semibold))
            addressText(url.absoluteString)
                .font(.system(size: 13)).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .accessibilityIdentifier("\(id).message")
            HStack(spacing: 8) {
                Button("Not Now", action: browser.notNow).buttonStyle(.glass)
                    .accessibilityIdentifier("\(id).not-now")
                Button("Open", action: browser.open).buttonStyle(.glassProminent)
                    .accessibilityIdentifier("\(id).open")
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(24)
    }
}

/// A `window.open` page over the card; `window.close()`, Esc and the × close it.
private struct Popup: View {
    let view: WKWebView
    let title: String
    let close: () -> Void
    @Environment(\.pageHidden) private var hidden

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                IconButton(symbol: "xmark", help: "Close", size: 22, action: close)
            }
            .padding(.leading, 11).padding(.trailing, 6).frame(height: 32)
            WebHost(view: view, hidden: hidden)
        }
        // Floating glass, not the card's fill: over a white page that left the × white on white.
        .clipShape(shape)
        .floatingGlass(in: shape)
        .shadow(radius: 12)
    }
}

/// Shows a web view the registry owns; the newest host adopts it. A card whose page goes takes its web view out of the
/// window with it, and the web view lives on; a kept page out of view hides the host (`SettlingHost.hide`). The host
/// fits it to itself once a motion ends, as a terminal's does.
struct WebHost: NSViewRepresentable {
    let view: WKWebView
    /// In a kept page out of view (as `TerminalHost`'s).
    let hidden: Bool

    func makeNSView(context: Context) -> SettlingHost {
        let host = SettlingHost(), box = NSView()
        host.clipsToBounds = true
        // Only an overview's tile disables its card.
        (view as? BrowserView)?.inTile = !context.environment.isEnabled
        // WebKit docks the Web Inspector beside the web view by frames that take y as growing upward: in a plain box,
        // which the (flipped) host fits.
        view.removeFromSuperview()
        // At the size it has: one set to the new host's zero size laid the page out again and drew it blank.
        box.frame.size = view.frame.size
        view.frame = box.bounds
        view.autoresizingMask = [.width, .height]
        box.addSubview(view)
        host.addSubview(box)
        return host
    }

    func updateNSView(_ host: SettlingHost, context _: Context) {
        host.hide(hidden)
    }
}

/// Row 1's icon: the page's, else the globe (also over a failed load).
struct BrowserIcon: View {
    let browser: Browser

    var body: some View {
        let icon = browser.failure == nil ? browser.icon?.image : nil
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().frame(width: 16, height: 16)
            } else {
                ProgramGlyph(icon: "globe")
            }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isStaticText)
        .accessibilityValue(icon == nil ? "globe" : "page")
        .accessibilityIdentifier("browser.\(browser.paneID).icon")
    }
}

/// A floated browser pane: the toolbar without the card buttons, under the floating window's title row.
struct FloatingBrowser: View {
    let browser: Browser
    let page: Page

    var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(browser: browser, page: page).padding(.horizontal, 11).frame(height: PaneCard.header)
                .padding(.vertical, PaneCard.floatingTop)
            BrowserCard(browser: browser, page: page)
        }
        .onAppear { browser.takeKeyboard() }
    }
}
