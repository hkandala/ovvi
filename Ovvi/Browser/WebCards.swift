import AppKit
import HerdrKit

extension PaneViewRegistry {
    /// Each kept web card keeps a WebKit process.
    static let spareWeb = UserDefaults.standard.string(forKey: "spareWebCards").flatMap { Int($0) } ?? 25
    static var recentWeb: [Kept] = []
    static var pictured: [Kept] = []
    struct Kept {
        weak var registry: PaneViewRegistry?
        let id: String
    }

    func showWeb(_ shown: Set<String>) {
        _ = GPUProcess.watch
        for id in webInView.subtracting(shown) {
            webView(id)?.takePicture()
            plugins[id]?.web.bridge?.shown(false)
        }
        for id in shown.subtracting(webInView) {
            plugins[id]?.web.bridge?.shown(true)
        }
        let touched = webInView.union(shown).filter { webView($0) != nil }
        webInView = shown
        Self.recentWeb.removeAll { kept in
            kept.registry == nil || kept.registry === self && (touched.contains(kept.id) || webView(kept.id) == nil)
        }
        let tracked = Set(Self.recentWeb.filter { $0.registry === self }.map(\.id)).union(touched)
        let untracked = Set(browsers.keys).union(plugins.keys).subtracting(tracked)
        Self.recentWeb = untracked.map { Kept(registry: self, id: $0) } + Self.recentWeb
            + touched.sorted { shown.contains($1) && !shown.contains($0) }.map { Kept(registry: self, id: $0) }
        Self.trim(terminals: Self.spare, web: Self.spareWeb)
    }

    static func trim(terminals: Int, web: Int) {
        while recent.count(where: { !$0.inView }) > terminals, let index = recent.firstIndex(where: { !$0.inView }) {
            recent.remove(at: index).hide()
        }
        let droppable = { (kept: Kept) in kept.registry?.droppable(kept.id) == true }
        while recentWeb.count(where: droppable) > web, let index = recentWeb.firstIndex(where: droppable) {
            let kept = recentWeb.remove(at: index)
            kept.registry?.drop(kept.id)
        }
    }

    func droppable(_ id: String) -> Bool {
        !webInView.contains(id) && pages?.floats(id) != true && plugins[id]?.dirty != true
            && browsers[id]?.popup == nil && webView(id) != nil
    }

    /// The snapshot's reply keeps the web view until it comes.
    func drop(_ id: String) {
        let view = webView(id)
        browsers[id] = nil
        plugins[id] = nil
        if let picture = view?.shot.image {
            return keep(id, picture)
        }
        view?.takePicture { [weak self] picture in
            withExtendedLifetime(view) {}
            // Not for a card made again meanwhile.
            if self?.webView(id) == nil {
                self?.keep(id, picture)
            }
        }
    }

    func keep(_ id: String, _ picture: CGImage) {
        guard pages?.withFloats.contains(where: { $0.store.panes.contains { $0.terminalID == id } }) == true
        else { return }
        pictures.removeAll { $0.id == id }
        pictures.append((id, picture))
        noted(id)
    }

    func noted(_ id: String) {
        Self.pictured.removeAll { $0.registry === self && $0.id == id }
        Self.pictured.append(Kept(registry: self, id: id))
        let bytes = { (kept: Kept) in kept.registry?.picture(kept.id).map { $0.bytesPerRow * $0.height } ?? 0 }
        Self.pictured.removeAll { bytes($0) == 0 }
        var total = Self.pictured.reduce(0) { $0 + bytes($1) }
        while total > 200 << 20, let oldest = Self.pictured.first {
            total -= bytes(oldest)
            Self.pictured.removeFirst()
            oldest.registry?.webView(oldest.id)?.shot.image = nil
            oldest.registry?.pictures.removeAll { $0.id == oldest.id }
        }
    }

    func keptPicture(_ id: String) -> CGImage? {
        pictures.firstIndex { $0.id == id }.map { pictures.remove(at: $0).picture }
    }

    func webView(_ id: String) -> BrowserView? {
        browsers[id]?.view ?? plugins[id]?.web.view
    }

    func takePictures(of ids: [String]) {
        for id in ids {
            terminals[id]?.takeSnapshot()
            webView(id)?.takePicture()
            if let picture = chatViews[id]?() {
                keep(id, picture)
            }
        }
    }

    func picture(_ id: String) -> CGImage? {
        webView(id)?.shot.image ?? pictures.last { $0.id == id }?.picture
    }
}
