import AppKit
import HerdrKit
import Observation
import SwiftUI
import WebKit

@MainActor @Observable
final class WebCard {
    let plugin: String

    private(set) var arg: String

    @ObservationIgnored weak var store: HostStore?
    @ObservationIgnored let view: WebCardView
    var bridge: Bridge?
    @ObservationIgnored var place: String?
    @ObservationIgnored var open: ((PluginManifest, String, String?, Opening, Bool) -> Void)?
    var dirty = false
    var ready = false
    var toast: Toast?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored var loads = 0
    @ObservationIgnored private var css = ""
    private(set) var title = ""
    @ObservationIgnored private var titleObservation: NSKeyValueObservation?

    init(plugin: String, arg: String, place: String?, store: HostStore) {
        self.plugin = plugin
        self.arg = arg
        self.place = place
        self.store = store
        let configuration = WKWebViewConfiguration()
        // Show Web Inspector opens nothing without it.
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.setURLSchemeHandler(PluginScheme.shared, forURLScheme: PluginScheme.name)
        view = WebCardView(frame: .zero, configuration: configuration)
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

    /// The user script also starts a page still loading or loaded again with the colors, so every first paint has them.
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
        Task {
            await bridge?.start()
            if bridge?.failure == nil {
                reload()
            }
        }
    }

    func show(_ arg: String, at place: String?) {
        bridge?.dropToast()
        toast = nil
        self.arg = arg
        self.place = place
        bridge?.place(arg, at: place)
    }

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

/// The content controller keeps its handler for good: a strong `card` would keep the card, its web view and its
/// process.
@MainActor
private final class Relay: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    weak var card: WebCard?
    private var reloaded = false

    init(card: WebCard) {
        self.card = card
    }

    /// Not the `async` form: WebKit starts each of its calls as a task off the main actor, and those reached the main
    /// actor out of order (a page's two `controls.set` of one control, the older one last). A task made here keeps
    /// the page's order.
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void)
    {
        guard let bridge = card?.bridge else { return replyHandler(nil, "Closed") }
        let body = message.body as? [String: Any] ?? [:]
        Task {
            let (reply, error) = await bridge.call(body)
            replyHandler(reply, error)
        }
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

    /// The system ends a page's process under memory pressure or after a long sleep.
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
        card.place = nil
        card.reload()
    }
}

final class WebCardView: BrowserView {
    /// WebKit sends a key again when the page leaves it.
    var handed: NSEvent?
    var keyboard: ((Bool) -> Void)?
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

    /// A view that leaves its window gets no `resignFirstResponder`.
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
    private var settings = AppSettings()
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
            + "; --app-text-size: \(settings.fontSize)px; color-scheme: \(look.dark ? "dark" : "light")"
        WebHost(view: card.view, hidden: hidden).onChange(of: css, initial: true) {
            card.theme(css, ["dark": look.dark, "style": look.style.rawValue, "textSize": settings.fontSize,
                             "colors": Dictionary(uniqueKeysWithValues: colors)])
        }
    }
}
