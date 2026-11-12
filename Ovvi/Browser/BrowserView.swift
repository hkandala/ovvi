import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

class BrowserView: WKWebView {
    var onKeyboard: (() -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    private var wantsKeyboard = false
    /// WebKit asks for the picked link's new window next (`createWebViewWith`).
    var opens: Opening?
    let shot = Shot()
    @MainActor @Observable final class Shot {
        var image: CGImage?
    }

    convenience init(store: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        // Sites that sniff for Safari work. Safari's version is the system's since macOS 26.
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(system.majorVersion).\(system.minorVersion)"
        configuration.applicationNameForUserAgent = "Version/\(version) Safari/605.1.15"
        // `_inspector show` opens nothing without it.
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        // A video's full-screen button and the page's `requestFullscreen`.
        configuration.preferences.isElementFullscreenEnabled = true
        self.init(frame: .zero, configuration: configuration)
        isInspectable = true
        allowsBackForwardNavigationGestures = true
        allowsMagnification = true
    }

    private static var warmViews: [ObjectIdentifier: BrowserView] = [:]

    /// A web view starts its page process at its first load: 0.1 s to seconds on a busy Mac, 1.4 s on CI, under the
    /// new card's loader. So a new card takes a warm view, whose process already runs, and the next one starts. A
    /// script, not a load, starts it: the view keeps no history, and its next load keeps the process. Only after a
    /// warm one was taken: the first ones start with `Browser.prewarm`, after the restored cards' own processes.
    static func take<View: BrowserView>(_ make: @escaping @MainActor @Sendable () -> View) -> View {
        guard let view = warmViews.removeValue(forKey: ObjectIdentifier(View.self)) as? View else { return make() }
        Task { warm(make) }
        return view
    }

    static func warm<View: BrowserView>(_ make: () -> View) {
        guard warmViews[ObjectIdentifier(View.self)] == nil else { return }
        let view = make()
        view.evaluateJavaScript("0")
        warmViews[ObjectIdentifier(View.self)] = view
    }

    static var focused: BrowserView? {
        // Not a web card (a subclass): there the keys size the terminals' text.
        (NSApp.keyWindow?.firstResponder as? BrowserView).flatMap { type(of: $0) == BrowserView.self ? $0 : nil }
    }

    func takeKeyboard() {
        wantsKeyboard = true
        // After SwiftUI's update: a first responder set during one is undone.
        DispatchQueue.main.async { [weak self] in
            guard let self, wantsKeyboard, let window, !isHiddenOrHasHiddenAncestor else { return }
            wantsKeyboard = false
            asking = true
            window.makeFirstResponder(self)
            asking = false
        }
    }

    private var asking = false

    /// With no page, the menu first: WebKit sends the key to the missing page, which drops it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        url == nil && window?.firstResponder === self && NSApp.mainMenu?.performKeyEquivalent(with: event) == true
            || super.performKeyEquivalent(with: event)
    }

    func zoom(_ step: Int) {
        pageZoom = step == 0 ? 1 : min(3, max(0.5, pageZoom + CGFloat(step) * 0.1))
        if step == 0 {
            magnification = 1
        }
    }

    /// WebKit's menu items hold no address: a relay sends the New Window item's action, and `opens` makes its window a
    /// tab or a side pane.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        opens = nil
        menu.items = menu.items.flatMap { item -> [NSMenuItem] in
            let id = item.identifier?.rawValue ?? ""
            guard !id.hasPrefix("WKMenuItemIdentifierDownload") else { return [] }
            guard id.hasSuffix("InNewWindow") else { return [item] }
            let tab = relay(item, item.title.replacingOccurrences(of: "New Window", with: "New Tab"), .tab)
            return id == "WKMenuItemIdentifierOpenLinkInNewWindow"
                ? [tab, relay(item, "Open Link to the Side", .side)] : [tab]
        }
    }

    private func relay(_ item: NSMenuItem, _ title: String, _ how: Opening) -> NSMenuItem {
        let relay = NSMenuItem(title: title, action: #selector(openLink), keyEquivalent: "")
        relay.target = self
        relay.representedObject = item
        relay.tag = how == .side ? 1 : 0
        return relay
    }

    @objc private func openLink(_ relay: NSMenuItem) {
        guard let item = relay.representedObject as? NSMenuItem, let action = item.action else { return }
        opens = relay.tag == 1 ? .side : .tab
        NSApp.sendAction(action, to: item.target, from: item)
    }

    /// A pick WebKit asks no window for (New Tab on a `mailto:` link) must not make the page's next popup a tab.
    override func mouseDown(with event: NSEvent) {
        opens = nil
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        opens = nil
        // In full screen, Esc is WebKit's.
        if fullscreenState != .notInFullscreen || onKey?(event) != true {
            super.keyDown(with: event)
        }
    }

    var pictured: (() -> Void)?

    /// At 1x: 6 MB for a full-window card on Retina, not 24. About 8 ms in WebKit's process, also out of a window.
    func takePicture(then taken: ((CGImage) -> Void)? = nil) {
        guard !bounds.isEmpty, url != nil else { return }
        let configuration = WKSnapshotConfiguration()
        // In points: the image comes at the screen's scale.
        configuration.snapshotWidth = NSNumber(value: bounds.width / ((window?.screen ?? NSScreen.main)?
                .backingScaleFactor ?? 2))
        takeSnapshot(with: configuration) { [weak self] image, _ in
            if let image = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                self?.shot.image = image
                self?.pictured?()
                taken?(image)
            }
        }
    }

    /// WebKit claims every drag over the page, whatever it carries, so a card's drop zones would never hear of a pane
    /// dragged over it.
    @objc(_hitTest:dragTypes:) private func hitTest(_ point: UnsafeMutablePointer<NSPoint>,
                                                    dragTypes types: NSSet?) -> NSView?
    {
        guard let hit = Self.webKitHit, types?.contains(UTType.ovviDrag.identifier) != true else { return nil }
        return hit(self, Self.dragHit, point, types)
    }

    private static let dragHit = NSSelectorFromString("_hitTest:dragTypes:")
    private typealias DragHit = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSPoint>, NSSet?) -> NSView?
    /// A private method: if its shape changes, nil, so a drag reaches the drop zones instead of a wrong argument.
    private static let webKitHit: DragHit? = {
        guard let method = class_getInstanceMethod(WKWebView.self, dragHit),
              let types = method_getTypeEncoding(method), String(cString: types) == "@32@0:8^{CGPoint=dd}16@24"
        else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: DragHit.self)
    }()

    func dropClaim() {
        wantsKeyboard = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsKeyboard, window != nil {
            takeKeyboard()
        }
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        if wantsKeyboard, window != nil {
            takeKeyboard()
        }
    }

    /// WebKit makes the view first responder itself when its page focuses an element, which would take the keys of the
    /// palette or the keyboard card. By then they resigned, so they take them back.
    override func becomeFirstResponder() -> Bool {
        let click = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(NSApp.currentEvent?.type)
        if !asking, !click, let window, let pages = WindowPages.windows.first(where: { $0.window === window }) {
            DispatchQueue.main.async {
                if pages.panelOpen {
                    NotificationCenter.default.post(name: FilterField.panelKeysTaken, object: nil)
                } else {
                    pages.current?.focusKeyboardCard()
                }
            }
            return false
        }
        let became = super.becomeFirstResponder()
        if became {
            onKeyboard?()
        }
        return became
    }
}

extension WKWebView {
    /// No public API shows it; cmux ships this.
    var inspector: NSObject? {
        let selector = NSSelectorFromString("_inspector")
        return responds(to: selector) ? perform(selector)?.takeUnretainedValue() as? NSObject : nil
    }

    var inspectorShown: Bool {
        // KVC on a name WebKit dropped would throw.
        guard let inspector, inspector.responds(to: NSSelectorFromString("isVisible")) else { return false }
        return inspector.value(forKey: "visible") as? Bool == true
    }

    func toggleInspector() {
        if inspectorShown {
            inspector?.perform(NSSelectorFromString("close"))
        } else {
            showInspector()
        }
    }

    func showInspector() {
        let show = NSSelectorFromString("show")
        guard let inspector, inspector.responds(to: show) else { return }
        // Docked each time: WebKit keeps the last choice of a window in the app's defaults.
        // ponytail: WebKit's private key; if it changes, the inspector opens where the user left it.
        UserDefaults.standard.removeObject(forKey: "__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached")
        inspector.perform(show)
    }
}

struct WebHost: NSViewRepresentable {
    let view: WKWebView
    let hidden: Bool

    func makeNSView(context _: Context) -> SettlingHost {
        let host = SettlingHost(), box = NSView()
        host.clipsToBounds = true
        // WebKit docks the Web Inspector beside the web view by frames that take y as growing upward: in a plain box,
        // which the (flipped) host fits.
        host.addSubview(box)
        adopt(box)
        return host
    }

    func updateNSView(_ host: SettlingHost, context _: Context) {
        if host.isHidden, !hidden, let box = host.subviews.first {
            adopt(box)
        }
        host.hide(hidden)
    }

    /// As `TerminalHost.adopt`: a shown host takes the web view, a hidden one only a view no host has, and takes it as
    /// its kept page comes into view.
    /// In full screen, WebKit's window has the view, and puts it back in its box at the end.
    private func adopt(_ box: NSView) {
        guard view.fullscreenState == .notInFullscreen, view.superview !== box, !hidden || view.superview == nil
        else { return }
        view.removeFromSuperview()
        // The new host's zero size would lay the page out again and draw it blank.
        if box.frame.isEmpty {
            box.frame.size = view.frame.size
        }
        view.frame = box.bounds
        view.autoresizingMask = [.width, .height]
        box.addSubview(view)
    }
}
