import HerdrKit
import Network
import WebKit

extension URL {
    var isWebAddress: Bool {
        scheme.map { ["http", "https"].contains($0.lowercased()) } ?? false
    }
}

extension Browser {
    static let loopback = ["localhost", "127.0.0.1", "::1"]

    static let safe = ["github.com", "gitlab.com", "bitbucket.org", "developer.apple.com",
                       "developer.mozilla.org", "docs.github.com", "vercel.com"]

    static func isLoopback(_ host: String) -> Bool {
        loopback.contains(host) || host.hasSuffix(".localhost")
    }

    /// Lowercase, as WebKit gives a page's address.
    static func origin(_ url: URL) -> String {
        ("\(url.scheme ?? "")://\(url.host ?? "")" + (url.port.map { ":\($0)" } ?? "")).lowercased()
    }

    static func url(_ text: String, local: Bool) -> URL? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= PaneLabel.argLimit else { return nil }
        let full = text.contains("://") ? text : "http://\(text)"
        guard let url = URL(string: full), url.absoluteString.count <= PaneLabel.argLimit,
              let scheme = url.scheme?.lowercased()
        else { return nil }
        return url.isWebAddress && url.host != nil || scheme == "file" && local ? url : nil
    }

    static func typed(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespaces)
        let host = URL(string: "http://\(text)")?.host?.lowercased() ?? ""
        let address = !text.contains(" ")
            && (text.contains("://") || text.contains(".") || host == "localhost" || host.contains(":"))
        guard !address, !text.isEmpty else { return text }
        let query = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return "https://www.google.com/search?q=\(query)"
    }

    private static var stores: [String: WKWebsiteDataStore] = [:]

    static func dataStore(_ machine: Machine) -> WKWebsiteDataStore {
        if let store = stores[machine.id] {
            return store
        }
        let id = UUID(uuidString: machine.isRemote ? machine.id : "6F767669-0000-4000-8000-746869734D61")
        let store = id.map { WKWebsiteDataStore(forIdentifier: $0) } ?? .nonPersistent()
        stores[machine.id] = store
        return store
    }

    /// WebKit keeps a store a window still uses.
    static func forget(_ machine: Machine) {
        stores[machine.id] = nil
        UserDefaults.standard.removeObject(forKey: approvalsKey(machine.id))
        UserDefaults.standard.removeObject(forKey: viaMacKey(machine.id))
        if let id = UUID(uuidString: machine.id) {
            Task { try? await WKWebsiteDataStore.remove(forIdentifier: id) }
        }
    }

    private static func viaMacCards(_ machine: Machine) -> [String] {
        UserDefaults.standard.stringArray(forKey: viaMacKey(machine.id)) ?? []
    }

    static func isViaMac(_ label: PaneLabel, _ store: HostStore) -> Bool {
        viaMacCards(store.machine).contains("\(store.session)/\(label.iid)")
    }

    static func start(_ label: PaneLabel, _ store: HostStore) {
        guard store.machine.isRemote,
              PluginSettings.shared.value(Registry.network, of: Registry.browser.id) == .text("mac")
        else { return }
        keep(true, label, store)
    }

    static func keep(_ viaMac: Bool, _ label: PaneLabel, _ store: HostStore) {
        let card = "\(store.session)/\(label.iid)"
        let cards = viaMacCards(store.machine).filter { $0 != card } + (viaMac ? [card] : [])
        UserDefaults.standard.set(Array(cards.suffix(200)), forKey: viaMacKey(store.machine.id))
    }

    private static func viaMacKey(_ id: String) -> String {
        "browserViaMac.\(id)"
    }

    // MARK: Origins

    /// The loopback is safe only as the machine's own: through This Mac's network it is This Mac's.
    func approved(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return url.isFileURL && store?.machine.isRemote == false }
        return !viaMac && Self.isLoopback(host) || Self.safe.contains(host)
            || host.hasSuffix(".vercel.app") || host.hasSuffix(".netlify.app")
            || Self.approvals(store?.machine.id ?? "").contains(Self.origin(url))
    }

    func approve(_ url: URL) {
        guard url.isWebAddress, !approved(url) else { return }
        Self.approve(Self.origin(url), store?.machine.id ?? "")
    }

    static func approvals(_ id: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: approvalsKey(id)) ?? []
    }

    static func approve(_ origin: String, _ id: String) {
        setApprovals(Array((approvals(id).filter { $0 != origin } + [origin]).suffix(200)), id)
    }

    static func setApprovals(_ sites: [String], _ id: String) {
        if sites.isEmpty {
            UserDefaults.standard.removeObject(forKey: approvalsKey(id))
        } else {
            UserDefaults.standard.set(sites, forKey: approvalsKey(id))
        }
    }

    static func clear(_ machine: Machine) {
        UserDefaults.standard.removeObject(forKey: approvalsKey(machine.id))
        dataStore(machine).removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }

    private static func approvalsKey(_ id: String) -> String {
        "browserApprovals.\(id)"
    }

    // MARK: Remote localhost

    static func alias(_ name: String) -> String {
        let words = name.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return words.isEmpty ? "machine" : words.joined(separator: "-")
    }

    /// WebKit never proxies a loopback name, so a remote machine's `localhost` loads as `<machine>.localhost`, which
    /// its proxy asks the machine for as `localhost`.
    static func web(_ url: URL, _ alias: String?) -> URL {
        guard let alias, loopback.contains(url.host?.lowercased() ?? ""),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.host = "\(alias).localhost"
        return parts.url ?? url
    }

    /// Any `<name>.localhost`, a renamed machine's too: the proxy asks the machine for `localhost`.
    static func shown(_ url: URL, _ alias: String?) -> URL {
        guard alias != nil, url.host?.lowercased().hasSuffix(".localhost") == true,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.host = "localhost"
        return parts.url ?? url
    }

    /// A page's images, fetches, frames and popups to a loopback name would reach This Mac: WebKit never proxies one.
    static func proxy(_ machine: Machine, _ store: WKWebsiteDataStore,
                      _ content: WKUserContentController) async -> SSHExec?
    {
        guard let ssh = await machine.exec() as? SSHExec, let port = try? await ssh.openProxy() else { return nil }
        guard let rule = await noLoopback.value else {
            await ssh.closeProxy()
            return nil
        }
        content.add(rule)
        store.proxyConfigurations = [ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: port))]
        return ssh
    }

    /// Every spelling of loopback WebKit loads without a proxy (`127.1`, `localhost.`, `[::ffff:7f00:1]`);
    /// `<name>.localhost` goes on to the proxy. Content rules have no alternation: one rule each.
    private static let noLoopback = Task { @MainActor in
        // Regexes in JSON strings: each backslash twice.
        let rules = [#"localhost[.]?[:/]"#, #"127\\."#, #"\\[::1\\]"#, #"\\[::ffff:7f"#]
            .map { #"^[^:]+://([^/]*@)?"# + $0 }
            .map { #"{"trigger":{"url-filter":"\#($0)"},"action":{"type":"block"}}"# }
        return try? await WKContentRuleListStore.default()
            .compileContentRuleList(
                forIdentifier: "ovvi-no-loopback",
                encodedContentRuleList: "[\(rules.joined(separator: ","))]",
            )
    }

    /// WebKit reports either code for a port the proxy finds closed or a name the machine cannot reach.
    func failureText(_ error: NSError, _ url: URL?) -> (text: String, hint: String?) {
        let place = url.map { [$0.host, $0.port.map(String.init)].compactMap(\.self).joined(separator: ":") } ?? ""
        let local = url?.host.map { Self.loopback.contains($0) } ?? false
        let machine = alias == nil ? nil : store?.machine.name
        let refused = error.code == NSURLErrorCannotConnectToHost || machine != nil && error.code == NSURLErrorBadURL
        return if refused, let machine, store?.state != .live {
            ("\(machine) is not connected", nil)
        } else if refused, local {
            ("Nothing answers on \(place)" + (machine.map { " on \($0)" } ?? ""), "Is the dev server running?")
        } else if refused, let machine {
            ("\(machine) cannot reach \(place)", nil)
        } else if error.code == NSURLErrorCannotFindHost {
            ("Cannot find \(place)", nil)
        } else {
            (error.localizedDescription, nil)
        }
    }
}
