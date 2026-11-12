import AppKit
import Carbon.HIToolbox
import HerdrKit
import Observation
import WebKit

@MainActor @Observable
final class Browser: NSObject {
    let terminalID: String
    var paneID: String
    let label: PaneLabel
    @ObservationIgnored weak var store: HostStore?
    private(set) var view: BrowserView
    var address = ""
    private(set) var title = ""
    var icon: (href: String, image: NSImage?)?
    private(set) var loading = false
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    var failure: (text: String, hint: String?)?
    private(set) var asking: URL?
    /// An empty web view draws white.
    var loaded = false
    var ready = false
    /// Over the card, not in a tab: OAuth needs its opener.
    var popup: (view: WKWebView, host: String)?
    var wantsAddress = false
    @ObservationIgnored private var claimed = false
    @ObservationIgnored private var reading = true
    @ObservationIgnored private var labelled: String
    /// A snapshot read ahead of the rename still has it.
    @ObservationIgnored private var replaced: String?
    @ObservationIgnored private var history: Data?
    @ObservationIgnored var reloaded = false
    @ObservationIgnored private var watches: [NSKeyValueObservation] = []
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private let remoteAlias: String?
    @ObservationIgnored private var proxy: Task<SSHExec?, Never>?
    private(set) var viaMac: Bool
    var alias: String? {
        viaMac ? nil : remoteAlias
    }

    var canReload: Bool {
        asking == nil && (loaded || failure != nil)
    }

    init(terminalID: String, paneID: String, label: PaneLabel, store: HostStore) {
        self.terminalID = terminalID
        self.paneID = paneID
        self.label = label
        labelled = label.arg
        // A claim held across a read is lost when the replaced pane's view leaves.
        reading = !label.arg.isEmpty
        self.store = store
        let machine = store.machine
        remoteAlias = machine.isRemote ? Self.alias(machine.name) : nil
        let viaMac = machine.isRemote && Self.isViaMac(label, store)
        self.viaMac = viaMac
        view = BrowserView(store: Self.dataStore(viaMac ? .thisMac : machine))
        super.init()
        wire()
        Task { await start() }
    }

    /// WebKit changes these on the main thread.
    private func watch() -> [NSKeyValueObservation] {
        func mirror(_ path: KeyPath<BrowserView, some Any>,
                    _ update: @escaping @MainActor (Browser) -> Void) -> NSKeyValueObservation
        {
            view.observe(path) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    if let self {
                        update(self)
                    }
                }
            }
        }
        return [
            mirror(\.isLoading) { $0.loading = $0.view.isLoading },
            mirror(\.estimatedProgress) { $0.progress = $0.view.estimatedProgress },
            mirror(\.canGoBack) { $0.canGoBack = $0.view.canGoBack },
            mirror(\.canGoForward) { $0.canGoForward = $0.view.canGoForward },
            mirror(\.title) { $0.title = $0.view.title ?? "" },
            mirror(\.url) { $0.showAddress() },
        ]
    }

    /// A failed load keeps its own address: WebKit goes back to the last page's.
    func showAddress() {
        guard failure == nil, let url = view.url, url.absoluteString != "about:blank" else { return }
        address = Self.shown(url, alias).absoluteString
        // A single-page app's route (`pushState`) finishes no navigation.
        if loaded {
            save()
        }
    }

    /// A process on the machine writes the label and the state file: only an approved or safe origin loads by itself.
    private func start() async {
        guard let store else { return }
        let state = await store.machine.exec().read(home: label.statePath(session: store.session))
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let saved = state?["url"] as? String
        history = saved == nil ? nil : (state?["history"] as? String).flatMap { Data(base64Encoded: $0) }
        reading = false
        defer {
            if claimed {
                claimed = false
                takeKeyboard()
            }
        }
        // Not over an address typed meanwhile.
        guard address.isEmpty, let url = url(saved ?? label.arg) else {
            ready = true
            return
        }
        address = url.absoluteString
        if approved(url) {
            restore(url)
        } else {
            asking = url
            ready = true
        }
    }

    func go(_ text: String) {
        guard let store, let url = url(Self.typed(text)) else { return }
        approve(url)
        load(url)
        replaced = labelled
        labelled = url.absoluteString
        // A typed load that fails saves nothing, and the saved address would win over the label after a relaunch.
        saving?.cancel()
        let path = label.statePath(session: store.session)
        Task { await store.machine.exec().remove(home: path) }
        let label = PaneLabel(plugin: label.plugin, iid: label.iid, arg: url.absoluteString)
        Task { await store.rename(pane: paneID, label: label.text) }
        view.takeKeyboard()
    }

    func open() {
        guard let url = asking else { return }
        asking = nil
        approve(url)
        restore(url)
    }

    func key(_ event: NSEvent) -> Bool {
        let code = Int(event.keyCode)
        if popup != nil, code == kVK_Escape {
            closePopup()
            return true
        }
        guard asking != nil, [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape].contains(code) else { return false }
        if code == kVK_Escape {
            notNow()
        } else {
            open()
        }
        return true
    }

    func notNow() {
        (asking, failure, history) = (nil, nil, nil)
        address = view.url.map { Self.shown($0, alias).absoluteString } ?? ""
    }

    func follow(_ arg: String) {
        guard arg != labelled, arg != replaced, store != nil else { return }
        replaced = nil
        labelled = arg
        guard let url = url(arg) else { return }
        address = url.absoluteString
        if approved(url) {
            load(url)
        } else {
            asking = url
        }
    }

    /// The history's current page must be approved too: a process on the machine writes the state file.
    private func restore(_ url: URL) {
        if let history {
            self.history = nil
            proxied {
                self.view.interactionState = history
                guard let current = (self.view.backForwardList.currentItem?.url).map({ Self.shown($0, self.alias) }),
                      Self.origin(current) != Self.origin(url), !self.approved(current) else { return }
                self.view.stopLoading()
                self.asking = current
            }
        } else {
            load(url)
        }
    }

    func reload() {
        guard asking == nil else { return }
        if failure != nil || view.url == nil, let url = URL(string: address) {
            load(url)
        } else {
            view.reload()
        }
    }

    private func load(_ url: URL) {
        (failure, asking) = (nil, nil)
        if url.isFileURL {
            // As Safari does: a page's media can sit in another folder. Scripts still cannot fetch other files.
            view.loadFileURL(url, allowingReadAccessTo: URL(filePath: "/"))
        } else {
            proxied { self.view.load(URLRequest(url: Self.web(url, self.alias))) }
        }
    }

    /// Never without the proxy: `<machine>.localhost` would reach This Mac.
    func proxied(_ load: @escaping () -> Void) {
        guard let proxy else { return load() }
        Task {
            let ssh = await proxy.value
            // Not on a network the card switched away from meanwhile.
            guard proxy == self.proxy else { return }
            guard ssh != nil else {
                // A listener that fails with no network can start on Reload.
                startProxy()
                failure = ("Ovvi could not start the proxy to \(store?.machine.name ?? "")", nil)
                ready = true
                return
            }
            load()
        }
    }

    func takeKeyboard() {
        if reading {
            claimed = true
        } else if address.isEmpty {
            wantsAddress = true
        } else {
            view.takeKeyboard()
        }
    }

    func dropClaim() {
        view.dropClaim()
        claimed = false
        // Only a change: Observation reports equal writes too.
        if wantsAddress {
            wantsAddress = false
        }
    }

    isolated deinit {
        // A full-screen video outlives its closed card otherwise: WebKit's window holds the view.
        view.closeAllMediaPresentations {}
        if let proxy {
            Task { await proxy.value?.closeProxy() }
        }
    }

    func url(_ text: String) -> URL? {
        store.flatMap { Self.url(text, local: !$0.machine.isRemote) }
    }

    /// The state file holds at most 256 KiB.
    func save() {
        guard let store, let url = view.url.map({ Self.shown($0, alias).absoluteString }), url != "about:blank"
        else { return }
        var state = ["url": url]
        if let history = view.interactionState as? Data, history.count < 128 << 10 {
            state["history"] = history.base64EncodedString()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }
        store.saveState(&saving, path: label.statePath(session: store.session), data: data, terminalID: terminalID)
    }
}

extension Browser {
    private func wire() {
        view.navigationDelegate = self
        view.uiDelegate = self
        view.onKey = { [weak self] in self?.key($0) ?? false }
        view.setAccessibilityIdentifier("browser.\(paneID)")
        watches = watch()
        startProxy()
    }

    private func startProxy() {
        if alias != nil, let machine = store?.machine {
            let data = view.configuration.websiteDataStore, content = view.configuration.userContentController
            proxy = Task { await Self.proxy(machine, data, content) }
        }
    }

    /// A data store's network cannot change: a new web view, with an empty back and forward list.
    func toggleNetwork() {
        guard let store, store.machine.isRemote else { return }
        viaMac.toggle()
        Self.keep(viaMac, label, store)
        let old = view, keyboard = old.window?.firstResponder === old
        old.navigationDelegate = nil
        old.uiDelegate = nil
        old.stopLoading()
        if let proxy {
            Task { await proxy.value?.closeProxy() }
        }
        proxy = nil
        view = BrowserView(store: Self.dataStore(viaMac ? .thisMac : store.machine))
        (view.onKeyboard, view.pictured) = (old.onKeyboard, old.pictured)
        wire()
        closePopup()
        if keyboard {
            view.takeKeyboard()
        }
        (loaded, ready, failure) = (false, false, nil)
        guard asking == nil, let url = URL(string: address) else {
            ready = true
            return
        }
        approve(url)
        load(url)
    }
}
