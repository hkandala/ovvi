import HerdrKit
import SwiftUI
import WebKit

extension Page {
    func browser(_ pane: HostStore.Pane) -> Browser? {
        guard let terminalID = pane.terminalID, let label = pane.browser else { return nil }
        return terminals.browser(pane, label, terminalID: terminalID, store: store)
    }

    /// Builds no card: menus ask for every tab's title.
    func browserTitle(_ pane: HostStore.Pane, _ label: PaneLabel) -> String? {
        let browser = pane.terminalID.flatMap { terminals.browsers[$0] }
        let address = browser?.address ?? label.arg
        return browser.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? URL(string: address)?.host
            ?? (address.isEmpty ? nil : address)
    }
}

extension CommandList {
    static func browser(_ browser: Browser?, chooser: Chooser?) -> [Command] {
        [
            Command(
                section: .view,
                title: "Reload Page",
                key: browser == nil ? nil : .hotkey("browser.reload"),
                symbol: "arrow.clockwise",
                keywords: "refresh browser",
                enabled: browser?.canReload == true,
            ) { browser?.reload() },
            Command(
                section: .edit,
                title: "Open Location",
                key: browser == nil && chooser == nil ? nil : .hotkey("browser.location"),
                symbol: "link",
                keywords: "address url browser folder",
                enabled: browser != nil || chooser != nil,
                action: {
                    browser?.wantsAddress = true
                    chooser?.editing = true
                },
            ),
            Command(
                section: .edit,
                title: "Show Web Inspector",
                key: browser == nil ? nil : .hotkey("browser.inspector"),
                symbol: "hammer",
                keywords: "developer tools devtools browser",
                enabled: browser?.loaded == true,
            ) { browser?.view.showInspector() },
        ]
    }
}

struct BrowserCard: View {
    let browser: Browser
    let page: Page
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
            // The hidden web view takes no click.
            .overlay {
                if !shows {
                    cover.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(.rect)
                }
            }
            .overlay {
                if let popup = browser.popup {
                    Popup(view: popup.view, title: popup.host, close: browser.closePopup).padding(24)
                }
            }
            // No fade over a picture: half way, both show the card's fill through.
            .animation(Animation.reduced || browser.view.shot.image != nil ? nil
                : .easeOut(duration: 0.15), value: browser.ready)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("browser.\(browser.paneID).card")
    }

    @ViewBuilder private var cover: some View {
        // As Reload and Return: a page waiting for Open wins over an older failure.
        if let url = browser.asking {
            Asking(browser: browser, url: url)
        } else if let failure = browser.failure {
            failed(failure.text, hint: failure.hint)
        } else if !browser.ready {
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
        .scrollsWhenShort()
    }
}

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
        // Not the card's fill: over a white page the × is white on white.
        .clipShape(shape)
        .floatingGlass(in: shape)
        .shadow(radius: 12)
    }
}

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
        .readableText(icon == nil ? "globe" : "page")
        .accessibilityIdentifier("browser.\(browser.paneID).icon")
    }
}

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
