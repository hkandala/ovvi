import HerdrKit
import SwiftUI

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
        // Only Ovvi's own PNG: `NSImage` reads PDF and more.
        self.icon = icon.flatMap { $0.utf8.count <= 16 << 10 && $0.hasPrefix("iVBORw0KGgo") ? $0 : nil }
    }

    /// The page's title on one line, else its host, else its file's name. 200 characters are past the row's width:
    /// a process on the machine writes the title.
    var shown: String {
        title.isEmpty ? URL(string: url).map { $0.host() ?? $0.lastPathComponent } ?? url
            : String(title.prefix(200)).replacing(/\s+/, with: " ")
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

    /// After any change in flight: a pick just before shows.
    static func pages(on machine: Machine) async -> [ClosedBrowserPage] {
        await changing[machine.id]?.value
        return await read(machine)
    }

    /// A pick reopens the page, so it leaves the list.
    static func reopen(_ closed: ClosedBrowserPage, how: Opening, from browser: Browser, page: Page) async {
        change(page.store.machine) { $0.filter { $0.url != closed.url } }
        await page.openFromPlugin(Registry.browser, arg: closed.url, from: browser.terminalID, how: how,
                                  background: how != .here)
    }
}

/// A popover, not an `NSMenu`, for the floating panels' tint (the material `floatingGlass` puts under its glass): a
/// menu's glass is too thin over a busy page. As a link: ⌘-click in the background, ⌥-click to the side, ⌘⌥-click
/// in the Mac's browser.
struct ClosedPagesPopover: View {
    struct Shown: Identifiable {
        let id = UUID()
        let pages: [ClosedBrowserPage]
    }

    let pages: [ClosedBrowserPage]
    let pick: (ClosedBrowserPage, Opening) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recently Closed").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .accessibilityAddTraits(.isHeader)
            if pages.isEmpty {
                EmptyState(symbol: "clock.arrow.circlepath", title: "No Recently Closed Pages", compact: true,
                           id: "browser.closed.empty")
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(pages.enumerated()), id: \.offset) { index, closed in
                Button {
                    pick(closed, PaneSurfaceView.linkKey(NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags)
                        ?? .here)
                } label: {
                    HStack(spacing: 8) {
                        icon(closed)
                        Text(closed.shown).lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                }
                .buttonStyle(ChromeStyle(radius: 6))
                .help(closed.shown + "\n" + closed.url)
                .accessibilityIdentifier("browser.closed.\(index)")
            }
        }
        .padding(6)
        .frame(width: 320)
        .presentationBackground(.regularMaterial)
    }

    @ViewBuilder
    private func icon(_ closed: ClosedBrowserPage) -> some View {
        if let image = closed.icon.flatMap({ Data(base64Encoded: $0) }).flatMap(NSImage.init(data:)) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: 16, height: 16)
                .accessibilityHidden(true)
        } else {
            ProgramGlyph(icon: "globe")
        }
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
