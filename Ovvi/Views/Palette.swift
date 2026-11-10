import HerdrKit
import SwiftUI

struct Palette: View {
    let pages: WindowPages
    let page: Page
    let commands: CommandList
    @Binding var open: Bool
    let height: CGFloat
    @State private var sub: Command?
    @State private var lit: String?
    @State private var kept: String?
    @State private var pasted: (filter: String, path: String)?
    /// Made once: made again on each body, the list would follow every change of a tab's title or panes while open.
    @State private var made: Made?

    private struct Made {
        let commands: [(item: FilterList.Item, keywords: String)]
        let places: [(item: FilterList.Item, keywords: String)]
        let start: Int
    }

    var body: some View {
        let made = made ?? make()
        let command = sub
        VStack(alignment: .leading, spacing: 2) {
            if let command {
                Text(Self.pageTitle(command)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.bottom, 2)
                    .accessibilityIdentifier("palette.title")
                    .accessibilityAddTraits(.isHeader)
            }
            palette(command, made)
        }
        .padding([.horizontal, .top], 10)
        .frame(width: 480)
        .floatingGlass(in: .panel)
        .task(id: lit) {
            guard command?.previews == true, let lit,
                  await (try? Task.sleep(for: .seconds(0.75))) != nil,
                  kept != nil else { return }
            command?.menu.first { lit == Self.choiceID($0) }?.action()
        }
        // The first body's: later ones read no tab or pane.
        .onAppear { self.made = made }
        .onDisappear { putBack() }
    }

    private func palette(_ command: Command?, _ made: Made) -> some View {
        FilterList(
            prompt: command?.field?.prompt ?? (command?.name == nil ? "Search" : "Name"),
            fieldSymbol: command?.field != nil ? command?.symbol : command?.name == nil ? "magnifyingglass" : "pencil",
            name: "palette",
            items: command.map(subItems) ?? { rootItems($0, made) },
            start: command.map(start) ?? made.start,
            maxHeight: min(460, max(84, height - 154)),
            // Only a preview page reads it: on the others each new light draws the whole palette again.
            lit: command?.previews == true ? $lit : nil,
            text: command?.name?.current ?? "",
            submit: command?.name.map { name in { text in Task { await name.save(text) } } } ?? command?.field?.open,
            typed: command == nil && commands.floating == nil ? { await check($0) } : nil,
            back: sub == nil ? nil : { back() },
            rowHeight: 32,
            table: true,
            inset: 10,
        ) { open = false }
            .controlSize(.large)
            .id(sub?.title)
    }

    static func choiceID(_ choice: Command) -> String {
        "choice.\(choice.id ?? choice.title)"
    }

    static func pageTitle(_ command: Command) -> String {
        command.title.replacing("…", with: "")
    }

    private func rootItems(_ filter: String, _ made: Made) -> [FilterList.Item] {
        let commands = made.commands, places = made.places
        guard !filter.trimmingCharacters(in: .whitespaces).isEmpty else {
            let rows = (places + commands).map(\.item)
            return Command.Group.allCases.flatMap { group in rows.filter { $0.section == group.rawValue } }
        }
        let open = pasted.flatMap { pasted in
            pasted.filter == filter ? FilterList.Item(id: "open-path", symbol: "doc", title: "Open \(pasted.path)",
                                                      act: { page.open(resolved: pasted.path) }) : nil
        }
        return [open].compactMap(\.self) + (commands + places).enumerated().compactMap { index, row in
            [row.item.title.fuzzyScore(filter), row.keywords.fuzzyScore(filter).map { $0 + 3 }].compactMap(\.self)
                .min().map { score in
                    let options: String.CompareOptions = [.anchored, .caseInsensitive, .diacriticInsensitive]
                    let starts = row.item.title.range(of: filter, options: options) != nil
                    let whole = row.item.title.compare(filter, options: options) == .orderedSame
                    return (score: score, rest: whole ? 0 : starts ? 1 : 2, index: index, item: row.item)
                }
        }
        .sorted { ($0.score, $0.rest, $0.index) < ($1.score, $1.rest, $1.index) }
        .map { row in
            var item = row.item
            (item.note, item.section) = (item.section, nil)
            return item
        }
    }

    private func make() -> Made {
        let floating = commands.floating != nil
        let start = floating ? 0 : page.selectedWorkspace?.tabs.firstIndex { $0.id == page.selectedTab?.id } ?? 0
        return Made(commands: commandRows(commands.all), places: floating ? [] : placeRows(), start: start)
    }

    private func commandRows(_ list: [Command]) -> [(item: FilterList.Item, keywords: String)] {
        Command.Section.allCases.filter { ![.tabs, .workspaces, .sessions].contains($0) }
            .flatMap { section in list.filter { $0.section == section } }
            .filter { $0.enabled && $0.key != .palette }.map { command in
                let opens = !command.menu.isEmpty || command.name != nil || command.field != nil
                let title = command.checked
                    .flatMap { command.setting ? "Turn \($0 ? "Off" : "On") \(command.title)" : nil }
                    ?? (opens ? Self.pageTitle(command) : command.title)
                let item = FilterList.Item(id: "command.\(command.title)", symbol: command.symbol, title: title,
                                           keys: command.key?.caps ?? [],
                                           section: (command.group ?? command.section.group).rawValue, opens: opens,
                                           act: {
                                               if opens {
                                                   sub = command
                                                   kept = command.previews
                                                       ? command.menu.first { $0.checked == true }?.title : nil
                                               } else {
                                                   command.action()
                                               }
                                           })
                return (item, command.keywords)
            }
    }

    private func placeRows() -> [(item: FilterList.Item, keywords: String)] {
        let tabs = (page.selectedWorkspace?.tabs ?? []).map { tab in
            FilterList.Item(id: "tab.\(tab.id)", pane: page.stack(tab).first, title: page.titleText(tab),
                            section: Command.Group.tabs.rawValue, act: {
                                if let workspace = page.selectedWorkspace,
                                   workspace.tabs.contains(where: { $0.id == tab.id })
                                {
                                    page.select(workspace, tab: tab.id)
                                }
                            })
        }
        let workspaces = pages.list.flatMap { other in
            other.store.workspaces.map { workspace in
                FilterList.Item(id: "workspace.\(other.id).\(workspace.id)", symbol: "folder",
                                title: workspace.label, detail: other.id,
                                section: Command.Group.workspaces.rawValue, act: {
                                    if other.store.workspaces.contains(where: { $0.id == workspace.id }) {
                                        pages.show(other)
                                        other.select(workspace)
                                    }
                                })
            }
        }
        let sessions = pages.list.map { other in
            FilterList.Item(id: "session.\(other.id)", symbol: "rectangle.stack", title: other.id,
                            section: Command.Group.sessions.rawValue, act: { pages.show(other) })
        }
        return tabs.map { ($0, "") } + workspaces.map { ($0, $0.detail) } + sessions.map { ($0, "") }
    }

    private func subItems(_ command: Command) -> (String) -> [FilterList.Item] {
        { filter in
            command.menu.filter { $0.enabled && $0.title.fuzzyScore(filter) != nil }.map { choice in
                let current = command.previews ? choice.title == kept : choice.checked == true
                let symbol = current ? "checkmark" : choice.symbol
                return FilterList.Item(id: Self.choiceID(choice), symbol: symbol, program: choice.program,
                                       title: choice.title,
                                       section: choice.heading, act: {
                                           kept = nil
                                           choice.action()
                                       })
            }
        }
    }

    private func check(_ filter: String) async {
        let text = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["/", "~", "./", "../"].contains(where: text.hasPrefix) else { return pasted = nil }
        // Not each key of a typed path: a remote machine's checks share its one relay.
        guard await (try? Task.sleep(for: .milliseconds(150))) != nil else { return }
        let path = await page.resolve(text)
        if !Task.isCancelled {
            pasted = path.map { (filter, $0) }
        }
    }

    private func start(_ command: Command) -> Int {
        command.menu.filter(\.enabled).firstIndex { command.previews ? $0.title == kept : $0.checked == true } ?? 0
    }

    private func back() {
        putBack()
        sub = nil
    }

    private func putBack() {
        if let kept {
            sub?.menu.first { $0.title == kept }?.action()
        }
        kept = nil
    }
}
