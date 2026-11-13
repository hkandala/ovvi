import AppKit
import HerdrKit

/// The browser pages closed on a machine, newest first, in one file on that machine: every device and session of
/// the machine shares it.
struct ClosedBrowserPage: Equatable {
    let url: String
    let title: String

    /// The page's title, else its host, else its file's name.
    var shown: String {
        let name = title.isEmpty ? URL(string: url).map { $0.host() ?? $0.lastPathComponent } ?? url : title
        return name.count > 60 ? name.prefix(59) + "…" : name
    }
}

@MainActor
enum ClosedPages {
    static let path = ".local/state/ovvi/closed-pages.json"
    static let most = 20
    /// One change at a time per machine: two closes in a row read and write the file in turn.
    private static var changing: [String: Task<Void, Never>] = [:]

    /// A process on the machine writes the file: anything but a list of addresses with titles reads as none.
    static func read(_ machine: Machine) async -> [ClosedBrowserPage] {
        await changing[machine.id]?.value
        return await load(machine)
    }

    private static func load(_ machine: Machine) async -> [ClosedBrowserPage] {
        let text = await machine.exec().read(home: path)
        let list = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [[String: Any]] } ?? []
        return list.compactMap { entry in
            (entry["url"] as? String).map { ClosedBrowserPage(url: $0, title: entry["title"] as? String ?? "") }
        }
    }

    /// ponytail: two devices that close pages on one machine at the same moment keep one's; a lock if that shows.
    static func change(_ machine: Machine, _ change: @escaping ([ClosedBrowserPage]) -> [ClosedBrowserPage]) {
        let previous = changing[machine.id]
        changing[machine.id] = Task {
            await previous?.value
            let pages = await change(load(machine)).prefix(most).map { ["url": $0.url, "title": $0.title] }
            guard let data = try? JSONSerialization.data(withJSONObject: pages) else { return }
            await machine.exec().write(home: path, String(decoding: data, as: UTF8.self))
        }
    }

    static func add(_ closed: [ClosedBrowserPage], _ machine: Machine) {
        guard !closed.isEmpty else { return }
        change(machine) { pages in closed + pages.filter { page in !closed.contains { $0.url == page.url } } }
    }

    /// A pick reopens the page, so it leaves the list. As a link: ⌘-click in the background, ⌥-click to the side,
    /// ⌘⌥-click in the Mac's browser.
    static func menu(for browser: Browser, page: Page, under view: MenuAnchor.Spot) async {
        let machine = page.store.machine, pages = await read(machine)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: "Recently Closed"))
        var picked: (page: ClosedBrowserPage, how: Opening)?
        for (index, closed) in pages.enumerated() {
            let action = MenuAction {
                let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                picked = (closed, PaneSurfaceView.linkKey(flags) ?? .here)
            }
            let item = menu.addItem(withTitle: closed.shown, action: #selector(MenuAction.fire), keyEquivalent: "")
            item.subtitle = URL(string: closed.url)?.host()
            item.target = action
            item.representedObject = action
            item.toolTip = closed.url
            item.identifier = .init("browser.closed.\(index)")
        }
        if pages.isEmpty {
            menu.addItem(withTitle: "No Recently Closed Pages", action: nil, keyEquivalent: "").isEnabled = false
        }
        // AppKit returns once the menu closed, after the picked item's action.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
        guard let picked else { return }
        change(machine) { $0.filter { $0 != picked.page } }
        let url = picked.page.url, how = picked.how
        guard how != .mac else {
            return Links.open(TerminalLink(range: 0 ..< 0, kind: .web, target: url), how: .mac,
                              from: browser.terminalID, page: page)
        }
        await page.open(Registry.browser, arg: url, from: browser.terminalID, how: how, background: how != .here)
    }
}

extension HostStore {
    /// The browser pages a close takes go to the machine's list once it closed them. Their state files have the
    /// pages' current address and title; the label has the address a card never loaded past.
    func keepingClosedPages(_ close: Close, _ action: @escaping (any Multiplexer) async throws -> Void)
        -> (any Multiplexer) async throws -> Void
    {
        let labels = panes(closedBy: close).compactMap(\.browser), machine = machine, session = session
        guard !labels.isEmpty else { return action }
        return { client in
            // Ahead of the close: a pane's close removes its state file.
            var pages: [ClosedBrowserPage] = []
            for label in labels {
                let text = await machine.exec().read(home: label.statePath(session: session))
                let state = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let url = state?["url"] as? String ?? label.arg
                if !url.isEmpty {
                    pages.append(ClosedBrowserPage(url: url, title: state?["title"] as? String ?? ""))
                }
            }
            try await action(client)
            ClosedPages.add(pages, machine)
        }
    }
}
