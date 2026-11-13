import AppKit
import HerdrKit

/// The browser pages closed on a machine, newest first, in one file on that machine: every device and session of
/// the machine shares it.
nonisolated struct ClosedBrowserPage {
    let url: String
    let title: String
    /// The page's icon, a 32 px PNG in base64, as the state file has it.
    let icon: String?

    /// Only an address a browser card there could show, and an icon of 16 KiB at most: a process on the machine
    /// writes the file and the labels.
    init?(url: String, title: String, icon: String?, local: Bool) {
        guard let url = Browser.url(url, local: local) else { return nil }
        self.url = url.absoluteString
        self.title = title
        self.icon = icon.flatMap { $0.count <= 16 << 10 ? $0 : nil }
    }

    /// The page's title, else its host, else its file's name.
    var shown: String {
        title.isEmpty ? URL(string: url).map { $0.host() ?? $0.lastPathComponent } ?? url : title
    }

    var entry: [String: String] {
        ["url": url, "title": title, "icon": icon].compactMapValues(\.self)
    }
}

@MainActor
enum ClosedPages {
    static let path = ".local/state/ovvi/closed-pages.json"
    static let most = 20
    /// One change at a time per machine: two closes in a row read and write the file in turn.
    private static var changing: [String: Task<Void, Never>] = [:]

    private static func read(_ machine: Machine) async -> [ClosedBrowserPage] {
        let text = await machine.exec().read(home: path)
        let list = text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [[String: Any]] } ?? []
        return Array(list.lazy.compactMap { entry in
            (entry["url"] as? String).flatMap {
                ClosedBrowserPage(url: $0, title: entry["title"] as? String ?? "", icon: entry["icon"] as? String,
                                  local: !machine.isRemote)
            }
        }.prefix(most))
    }

    /// ponytail: two devices that close pages on one machine at the same moment keep one's; a lock if that shows.
    static func change(_ machine: Machine, _ change: @escaping ([ClosedBrowserPage]) -> [ClosedBrowserPage]) {
        let previous = changing[machine.id]
        changing[machine.id] = Task {
            await previous?.value
            let pages = await change(read(machine)).prefix(most).map(\.entry)
            guard let data = try? JSONSerialization.data(withJSONObject: pages) else { return }
            await machine.exec().write(home: path, String(decoding: data, as: UTF8.self))
        }
    }

    static func add(_ closed: [ClosedBrowserPage], _ machine: Machine) {
        guard !closed.isEmpty else { return }
        change(machine) { pages in closed + pages.filter { page in !closed.contains { $0.url == page.url } } }
    }

    /// One line, at most 320 pt wide in the menu's font, with an ellipsis: a menu grows to its widest row.
    private static func cut(_ title: String) -> String {
        let font = [NSAttributedString.Key.font: NSFont.menuFont(ofSize: 0)]
        guard (title as NSString).size(withAttributes: font).width > 320 else { return title }
        var shown = title
        while !shown.isEmpty, ((shown + "…") as NSString).size(withAttributes: font).width > 320 {
            shown.removeLast()
        }
        return shown.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The icon in the title: macOS 27 draws no `NSMenuItem.image` in an app's menus, and draws text attachments.
    private static func row(_ title: String, icon: String?) -> NSAttributedString {
        let globe = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor]))
        let attachment = NSTextAttachment()
        attachment.image = icon.flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:)) ?? globe
        attachment.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)
        let row = NSMutableAttributedString(attachment: attachment)
        row.append(NSAttributedString(string: "  " + title, attributes: [.font: NSFont.menuFont(ofSize: 0)]))
        return row
    }

    /// The icon for the state file: 32 px, so a closed page's entry stays small.
    static func png(_ image: NSImage) -> String? {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)
        guard let bitmap, let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])?.base64EncodedString()
    }

    /// A pick reopens the page, so it leaves the list. As a link: ⌘-click in the background, ⌥-click to the side,
    /// ⌘⌥-click in the Mac's browser.
    static func menu(for browser: Browser, page: Page, under view: MenuAnchor.Spot) async {
        let machine = page.store.machine
        await changing[machine.id]?.value
        let pages = await read(machine)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: "Recently Closed"))
        var picked: (page: ClosedBrowserPage, how: Opening)?
        for (index, closed) in pages.enumerated() {
            let action = MenuAction {
                let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                picked = (closed, PaneSurfaceView.linkKey(flags) ?? .here)
            }
            let item = menu.addItem(withTitle: cut(closed.shown), action: #selector(MenuAction.fire),
                                    keyEquivalent: "")
            item.attributedTitle = row(item.title, icon: closed.icon)
            item.target = action
            item.representedObject = action
            item.toolTip = closed.shown + "\n" + closed.url
            item.identifier = .init("browser.closed.\(index)")
        }
        if pages.isEmpty {
            menu.addItem(withTitle: "No Recently Closed Pages", action: nil, keyEquivalent: "").isEnabled = false
        }
        // Not for a card that closed during a remote read.
        guard view.window != nil else { return }
        await menu.popUp(at: NSPoint(x: 0, y: -4), in: view)
        guard let picked else { return }
        change(machine) { $0.filter { $0.url != picked.page.url } }
        await page.openFromPlugin(Registry.browser, arg: picked.page.url, from: browser.terminalID, how: picked.how,
                                  background: picked.how != .here)
    }
}

extension HostStore {
    /// The browser pages a close takes go to the machine's list once it closed them. Their state files have the
    /// pages' current address and title; the label has the address a card never loaded past.
    func keepingClosedPages(_ close: Close, _ action: @escaping (any Multiplexer) async throws -> Void)
        -> (any Multiplexer) async throws -> Void
    {
        let labels = panes(closedBy: close).compactMap(\.browser), machine = machine, session = session
        let local = !machine.isRemote
        guard !labels.isEmpty else { return action }
        return { client in
            // Ahead of the close: a pane's close removes its state file.
            let exec = await machine.exec()
            let pages = await withTaskGroup(of: ClosedBrowserPage?.self) { group in
                for label in labels {
                    group.addTask {
                        let text = await exec.read(home: label.statePath(session: session))
                        let state = text.flatMap {
                            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
                        }
                        return ClosedBrowserPage(url: state?["url"] as? String ?? label.arg,
                                                 title: state?["title"] as? String ?? "",
                                                 icon: state?["icon"] as? String, local: local)
                    }
                }
                var pages: [ClosedBrowserPage] = []
                for await page in group {
                    pages += page.map { [$0] } ?? []
                }
                return pages
            }
            try await action(client)
            ClosedPages.add(pages, machine)
        }
    }
}
