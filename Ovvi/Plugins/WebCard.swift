import AppKit
import HerdrKit
import Observation
import SwiftUI
import WebKit

/// A plugin card's content as its plugin's build (`PluginBuilds`), in a web view of its own: WebKit makes a
/// process per web view whatever the process pool. The page talks to the app through the plugin API (`Bridge`).
@MainActor @Observable
final class WebCard {
    /// Its plugin's id.
    let plugin: String

    /// The place shown: the plugin's argument. The label follows it (`Plugin.show`).
    private(set) var arg: String

    @ObservationIgnored weak var store: HostStore?
    @ObservationIgnored let view: WebCardView
    var bridge: Bridge?
    /// A linked open's landing, for the first load only (`ovvi.card.at`).
    @ObservationIgnored var place: String?
    /// Opens a link from the page, in the card or beside it (`Page.open(_:arg:at:from:how:)`).
    @ObservationIgnored var open: ((PluginManifest, String, String?, Opening, Bool) -> Void)?
    var dirty = false
    /// The page drew its first rows or its file: the loader goes.
    var ready = false
    var toast: Toast?
    @ObservationIgnored private var loaded = false
    /// Reloads asked for, so only the last one's page loads (`reload`).
    @ObservationIgnored var loads = 0
    @ObservationIgnored private var css = ""
    /// The page's `document.title`: the card's title while it is not empty (Git's commit subject).
    private(set) var title = ""
    @ObservationIgnored private var titleObservation: NSKeyValueObservation?

    init(plugin: String, arg: String, place: String?, store: HostStore) {
        self.plugin = plugin
        self.arg = arg
        self.place = place
        self.store = store
        let configuration = WKWebViewConfiguration()
        // The card's Show Web Inspector opens nothing without it.
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.setURLSchemeHandler(PluginScheme.shared, forURLScheme: PluginScheme.name)
        view = WebCardView(frame: .zero, configuration: configuration)
        // The card's fill draws behind the page.
        view.underPageBackgroundColor = .clear
        view.setValue(false, forKey: "drawsBackground")
        view.isInspectable = true
        let relay = Relay(card: self)
        configuration.userContentController.addScriptMessageHandler(relay, contentWorld: .page, name: "ovvi")
        view.navigationDelegate = relay
        titleObservation = view.observe(\.title) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.title = view.title ?? "" }
        }
    }

    /// The app's colors as CSS variables. The first call loads the page; the script also starts a page still loading
    /// or loaded again with them, so every first paint has them.
    func theme(_ css: String, _ theme: [String: Any]) {
        self.css = css
        if loaded {
            view.callAsyncJavaScript("document.documentElement.style.cssText = css", arguments: ["css": css],
                                     in: nil, in: .page)
        }
        // The page hears `theme` after its CSS variables changed.
        bridge?.theme = theme
        script()
        guard !loaded else { return }
        loaded = true
        // A plugin's page starts with its saved state, and not at all with an API too new.
        Task {
            await bridge?.start()
            if bridge?.failure == nil {
                reload()
            }
        }
    }

    /// Another place: the page draws it itself. The toast was the old place's, as a page loaded again drops it.
    func show(_ arg: String, at place: String?) {
        bridge?.dropToast()
        toast = nil
        self.arg = arg
        self.place = place
        bridge?.place(arg, at: place)
    }

    /// The card's context and colors (`Bridge.context`), in the page before its code runs.
    func script() {
        let card = (bridge?.context() ?? [:]).merging(["css": css]) { $1 }
        let json = (try? JSONSerialization.data(withJSONObject: card)).map {
            String(decoding: $0, as: UTF8.self)
        } ?? "{}"
        let content = view.configuration.userContentController
        content.removeAllUserScripts()
        content.addUserScript(WKUserScript(
            source: "window.ovvi_card = \(json); document.documentElement.style.cssText = window.ovvi_card.css",
            injectionTime: .atDocumentStart, forMainFrameOnly: true,
        ))
    }
}

/// The content controller keeps its handler for good: a strong one kept the card, its web view and its process.
@MainActor
private final class Relay: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    weak var card: WebCard?
    /// The page's process ended since the last load finished: it loads again once.
    private var reloaded = false

    init(card: WebCard) {
        self.card = card
    }

    func userContentController(_: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?)
    {
        guard let bridge = card?.bridge else { return (nil, "Closed") }
        return await bridge.call(message.body as? [String: Any] ?? [:])
    }

    /// The card's own page only: a Markdown file's HTML (a `<meta>` refresh, a form) would take the view, and the
    /// bridge with it, to any site or to another page.
    func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let card else { return .cancel }
        return url == PluginScheme.url(card.plugin) ? .allow : .cancel
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        reloaded = false
    }

    /// The system ends a page's process (memory pressure, a long sleep): the page loads again with its state now, once
    /// per load; one that ends it again before it loaded says so, with Reload, instead of a blank card.
    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        guard let card else { return }
        card.dirty = false
        guard !reloaded else {
            card.ready = true
            if let bridge = card.bridge, let manifest = bridge.plugin?.manifest {
                bridge.failure = .noted(manifest, PluginProblem(title: "The page stopped working",
                                                                text: "It stopped again as it loaded."))
            }
            return
        }
        reloaded = true
        // Where the user left it (the page's kept scroll), not a linked open's landing.
        card.place = nil
        card.reload()
    }
}

final class WebCardView: BrowserView {
    /// The ⇧⌘← or ⇧⌘→ the menu handed to the page: WebKit sends it again when the page leaves it, for Move Tab.
    var handed: NSEvent?
    /// A plugin page's `keyboard`.
    var keyboard: ((Bool) -> Void)?
    /// Back (true) or Forward, ⌃- and ⌃⇧- over the card, as VS Code's Go Back and Go Forward (⌘[ and ⌘] select a
    /// pane). The card takes them also with no place that way.
    var step: ((Bool) -> Void)?

    /// WebKit gives the page every ⌘ key first, and CodeMirror takes some of the app's: the menu goes first, as over a
    /// native text view.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let back = KeyboardShortcut.back.matches(event)
        if let step, back || KeyboardShortcut.forward.matches(event) {
            step(back)
            return true
        }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) == true || super.performKeyEquivalent(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            keyboard?(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            keyboard?(false)
        }
        return resigned
    }

    /// Its tab hidden, it leaves the window with no `resignFirstResponder`: the page hears it lost the keyboard.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            keyboard?(false)
        }
    }
}

struct WebCardContent: View {
    let card: WebCard
    @Environment(\.self) private var environment
    @Environment(\.look) private var look
    @Environment(\.litCard) private var lit
    @AppStorage("fontSize") private var textSize = PaneTerminal.fontSize
    @Environment(\.pageHidden) private var hidden

    var body: some View {
        let colors = [
            ("text", Color.primary), ("dim", look.paneButton), ("divider", look.divider),
            ("card", look.cardSolid(keyboard: lit)),
            ("accent", .accentColor), ("on-accent", Look.onAccent),
            ("working", look.working), ("needs-you", look.needsYou), ("finished", look.finished),
            ("error", look.error),
        ].map { name, color in
            let rgb = color.resolve(in: environment)
            return (name, "rgb(\(rgb.red * 255) \(rgb.green * 255) \(rgb.blue * 255) / \(rgb.opacity))")
        }
        let css = colors.map { "--\($0): \($1)" }.joined(separator: "; ")
            + "; --app-text-size: \(textSize)px; color-scheme: \(look.dark ? "dark" : "light")"
        WebHost(view: card.view, hidden: hidden).onChange(of: css, initial: true) {
            card.theme(css, ["dark": look.dark, "style": look.style.rawValue, "textSize": textSize,
                             "colors": Dictionary(uniqueKeysWithValues: colors)])
        }
    }
}
