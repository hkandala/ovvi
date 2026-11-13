import HerdrKit
import SwiftUI

/// Must match `kind` in plugins/builtin/explorer/src/place.ts.
enum ExplorerPlace: String, CaseIterable {
    case files, file, preview, markdown

    init(_ arg: String) {
        let ext = (arg as NSString).pathExtension.lowercased(), places = Registry.places
        if arg.hasSuffix("/") {
            self = .files
        } else if places["markdown", default: []].contains(ext) {
            self = .markdown
        } else {
            self = ["image", "pdf", "audio", "video", "binary"].contains { places[$0, default: []].contains(ext) }
                ? .preview : .file
        }
    }

    init?(plugin: String, _ arg: String) {
        guard plugin == "explorer" else { return nil }
        self.init(arg)
    }

    var symbol: String {
        switch self {
        case .files: "folder"
        case .file: "doc.text"
        case .preview: "photo"
        case .markdown: "doc.richtext"
        }
    }
}

extension PaneLabel {
    var symbol: String {
        manifest.map { ExplorerPlace(plugin: $0.id, arg)?.symbol ?? $0.icon } ?? Registry.missing
    }

    var manifest: PluginManifest? {
        Registry.plugin(plugin)
    }

    /// From the label alone: menus ask for every tab's title.
    var title: String {
        if manifest?.id == "git", let source = diffSource {
            return source == "uncommitted" ? "Working Tree" : String(source.prefix(7))
        }
        let name = (arg as NSString).lastPathComponent
        return name.isEmpty ? manifest?.name ?? plugin : name
    }
}

extension Page {
    func pluginTitle(_ pane: HostStore.Pane, _ label: PaneLabel) -> String {
        let title = pane.terminalID.flatMap { terminals.plugins[$0] }?.web.title ?? ""
        return title.isEmpty ? label.title : title
    }

    func cardLabel(_ pane: HostStore.Pane?) -> String {
        pane.map { pane in
            pane.plugin.flatMap { pane.browser == nil ? pluginTitle(pane, $0) : nil } ?? pane.cardTitle
        } ?? "terminal"
    }
}

extension Image {
    init(symbol name: String) {
        self = NSImage.own.contains(name) ? Image(name) : Image(systemName: name)
    }
}

extension NSImage {
    /// Material Design Icons' `source-branch` and `wrap`.
    static let own: Set = ["source.branch", "text.wrap"]

    static func symbol(_ name: String) -> NSImage? {
        own.contains(name) ? NSImage(named: name) : NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}

@MainActor @Observable
final class Plugin {
    let terminalID: String
    var paneID: String {
        didSet { name() }
    }

    private(set) var label: PaneLabel
    let manifest: PluginManifest
    let web: WebCard
    let header: Header

    init(terminalID: String, paneID: String, label: PaneLabel, manifest: PluginManifest, place: String?,
         store: HostStore)
    {
        self.terminalID = terminalID
        self.paneID = paneID
        self.label = label
        self.manifest = manifest
        web = WebCard(plugin: manifest.id, arg: label.arg, place: place, store: store)
        header = Header(manifest: manifest)
        name()
        web.bridge = Bridge(plugin: self)
        web.view.step = { [weak self] back in
            guard let self, back ? canGoBack : canGoForward else { return false }
            if back {
                goBack()
            } else {
                goForward()
            }
            return true
        }
    }

    func name() {
        let page = ExplorerPlace(plugin: manifest.id, web.arg)?.rawValue ?? manifest.id
        web.view.setAccessibilityIdentifier("\(page).\(paneID).page")
    }

    func handles(_ command: String) -> Bool {
        guard manifest.handles.contains(command) else { return false }
        if manifest.id == "git" {
            return PaneLabel(plugin: "git", iid: "", arg: web.arg).diffSource != nil
        }
        let place = ExplorerPlace(plugin: manifest.id, web.arg)
        return place != .preview && (place != .files || command == "find")
    }

    func command(_ name: String) {
        web.bridge?.event(name, NSNull())
    }

    var dirty: Bool {
        web.dirty
    }

    private(set) var back: [(arg: String, at: String?)] = []
    private(set) var forward: [(arg: String, at: String?)] = []
    /// A snapshot read ahead of a rename is no rename from elsewhere. Cleared once the last one returns: a write waits
    /// for the snapshot after it.
    @ObservationIgnored private var renamed: Set<String> = []
    @ObservationIgnored private var renaming = 0

    var canGoBack: Bool {
        !back.isEmpty
    }

    var canGoForward: Bool {
        !forward.isEmpty
    }

    func go(_ arg: String, at place: String?) {
        guard arg != web.arg else {
            web.bridge?.place(arg, at: place)
            return
        }
        guard PaneLabel(plugin: manifest.id, iid: label.iid, arg: arg).fits else { return }
        leave { plugin in
            plugin.back.append((plugin.web.arg, place ?? arg))
            plugin.forward = []
            plugin.show(arg, at: place)
        }
    }

    func goBack() {
        leave { plugin in
            guard let last = plugin.back.popLast() else { return }
            plugin.forward.append((plugin.web.arg, nil))
            plugin.show(last.arg, at: last.at)
        }
    }

    func goForward() {
        leave { plugin in
            guard let next = plugin.forward.popLast() else { return }
            plugin.back.append((plugin.web.arg, next.at ?? next.arg))
            plugin.show(next.arg, at: next.at)
        }
    }

    func reopen(as other: PluginManifest) {
        leave { plugin in
            let text = PaneLabel(plugin: other.id, iid: plugin.label.iid, arg: plugin.web.arg).text
            guard let store = plugin.web.store else { return }
            Task { [paneID = plugin.paneID] in await store.write { try await $0.rename(pane: paneID, label: text) } }
        }
    }

    func leave(_ then: @escaping (Plugin) -> Void) {
        guard web.dirty else { return then(self) }
        web.bridge?.dropToast()
        let name = (web.arg as NSString).lastPathComponent
        web.toast = Toast(text: "\(name) has unsaved edits.",
                          other: .init(title: "Discard", role: .destructive) { [weak self] in self.map(then) },
                          main: .init(title: "Keep Editing") {})
    }

    private func show(_ arg: String, at place: String?) {
        web.show(arg, at: place)
        name()
        let text = PaneLabel(plugin: manifest.id, iid: label.iid, arg: arg).text, paneID = paneID
        guard let store = web.store else { return }
        renamed.insert(arg)
        renaming += 1
        // Not `HostStore.rename`, which skips a label the last snapshot has: a quick Back renames to it again.
        Task {
            await store.write { try await $0.rename(pane: paneID, label: text) }
            renaming -= 1
            if renaming == 0 {
                renamed = []
            }
        }
    }

    /// ponytail: a place from elsewhere drops unsaved edits without asking.
    func follow(_ label: PaneLabel) {
        self.label = label
        let arg = label.arg
        if arg != web.arg, !renamed.contains(arg) {
            back.append((web.arg, nil))
            forward = []
            web.show(arg, at: nil)
            name()
        }
    }
}

struct BackForward: View {
    let plugin: Plugin
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "chevron.left", help: "Back", key: .hotkey("card.back"), size: 22) { plugin.goBack() }
                .disabled(!plugin.canGoBack)
                .accessibilityIdentifier("pane.\(plugin.paneID).go-back")
            IconButton(symbol: "chevron.right", help: "Forward", key: .hotkey("card.forward"), size: 22) {
                plugin.goForward()
            }
            .disabled(!plugin.canGoForward)
            .accessibilityIdentifier("pane.\(plugin.paneID).go-forward")
        }
        .foregroundStyle(look.paneButton)
    }
}

struct Toast {
    let text: String
    let other: Action?
    let main: Action

    struct Action {
        let title: String
        var role: ButtonRole?
        let run: () -> Void
    }
}

extension HostStore.Pane {
    var plugin: PaneLabel? {
        PaneLabel(label)
    }
}

extension HostStore {
    func newLabel(_ plugin: PluginManifest, arg: String) -> PaneLabel {
        let taken = Set(panes.compactMap { PaneLabel($0.label)?.iid })
        let label = PaneLabel(plugin: plugin.id, iid: PaneLabel.newIID(taken: taken), arg: arg)
        if plugin.id == Registry.browser.id {
            Browser.start(label, self)
        }
        return label
    }
}
