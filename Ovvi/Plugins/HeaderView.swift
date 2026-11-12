import AppKit
import HerdrKit
import SwiftUI

struct PluginHeader: View {
    let plugin: Plugin
    let page: Page

    var body: some View {
        // Only with bordered buttons: a row made again loses a typing field's keyboard.
        if plugin.header.controls.contains(where: { $0.style == "bordered" && $0.hidden != true }) {
            ViewThatFits(in: .horizontal) {
                row(words: true)
                row(words: false)
            }
        } else {
            row(words: false)
        }
    }

    private func row(words: Bool) -> some View {
        let controls = plugin.header.controls, history = plugin.manifest.history
        return HStack(spacing: 0) {
            if history {
                BackForward(plugin: plugin)
            }
            // By index, not by place among the shown: hiding one keeps a typing field's identity, and its keyboard.
            ForEach(controls.indices, id: \.self) { index in
                let control = controls[index]
                if control.hidden != true {
                    let before = controls[..<index].last { $0.hidden != true }
                    HeaderItem(control: control, plugin: plugin, page: page, words: words)
                        .disabled(control.enabled == false || control.busy == true)
                        .padding(.leading, before == nil && !history ? 0 : CGFloat(control.gap ?? 6))
                        .layoutPriority(control.type == "text" ? 1 : 0)
                }
            }
            if !controls.contains(where: { $0.hidden != true && ["spacer", "field"].contains($0.type) }) {
                Spacer(minLength: 0)
            }
        }
    }
}

private struct HeaderItem: View {
    let control: PluginManifest.Control
    let plugin: Plugin
    let page: Page
    let words: Bool
    @Environment(\.look) private var look

    var body: some View {
        let id = control.id ?? "", identifier = "pane.\(plugin.paneID).\(id)"
        // Each control its own identifier: one on the group would cover the segments' and the field's.
        switch control.type {
        case "button": button(id).accessibilityIdentifier(identifier)
        case "toggle": toggle(id).accessibilityIdentifier(identifier)
        case "segmented":
            let options = control.options ?? []
            let symbols = options.compactMap { option in option.symbol.map { (option.title ?? "", $0) } }
            Segments(id: identifier, options: options.map { ($0.title ?? "", $0.value ?? "") },
                     selection: Binding { control.value?.text ?? "" } set: { plugin.header.pick(id, .text($0)) },
                     symbols: Dictionary(symbols) { first, _ in first })
                .fixedSize()
        case "menu": HeaderMenu(control: control, header: plugin.header).accessibilityIdentifier(identifier)
        case "field" where control.style == "path":
            PathField(control: control, plugin: plugin, page: page, identifier: identifier)
        case "field":
            FilterField(prompt: control.placeholder ?? "Filter",
                        text: Binding { control.value?.text ?? "" } set: { plugin.header.pick(id, .text($0)) },
                        identifier: identifier, focus: plugin.header.focus[id] ?? 0)
                .onSubmit { plugin.header.pick(id, nil, submit: true) }
        case "text": text.accessibilityIdentifier(identifier)
        case "openWith": openWith.accessibilityIdentifier(identifier)
        default: Spacer(minLength: 0)
        }
    }

    /// One view whatever its state, so a click under way keeps its pressed state.
    private func button(_ id: String) -> some View {
        let title = control.title ?? ""
        return Group {
            if control.style == "bordered" {
                labeled(id, words: words).buttonStyle(.bordered).controlSize(.small)
            } else {
                labeled(id, icon: true).buttonStyle(ChromeStyle(radius: 5.5)).foregroundStyle(look.paneButton)
            }
        }
        .help(title)
        // In the label: XCUITest reads no button's value.
        .accessibilityLabel(control.label ?? control.badge.map { "\(title), \($0)" } ?? title)
    }

    private func labeled(_ id: String, words: Bool = false, icon: Bool = false) -> some View {
        Button { plugin.header.pick(id, nil) } label: {
            HStack(spacing: words ? 4 : 2) {
                if control.busy == true {
                    ProgressView().controlSize(.mini).frame(width: 14)
                } else {
                    Image(symbol: control.symbol ?? "questionmark").font(.system(size: 11)).frame(width: 14)
                }
                if words {
                    Text(control.title ?? "").fixedSize()
                }
                if let badge = control.badge {
                    Text(badge).font(.system(size: 11).monospacedDigit())
                }
            }
            .padding(.horizontal, icon ? 4 : 0)
            .frame(minWidth: icon ? 22 : nil, minHeight: icon ? 22 : nil)
        }
    }

    private func toggle(_ id: String) -> some View {
        let isOn = control.value == .bool(true), onSymbol = isOn ? control.onSymbol : nil
        return IconButton(symbol: onSymbol ?? control.symbol ?? "questionmark", help: control.title ?? "", size: 22) {
            plugin.header.pick(id, .bool(!isOn))
        }
        .foregroundStyle(isOn && control.onSymbol == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(look.paneButton))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityLabel(control.label ?? control.title ?? "")
    }

    private var text: some View {
        let path = control.style == "path"
        let parts: [String] = switch control.value {
        case let .list(list): path ? list : [list.joined(separator: " ")]
        case let .text(text): [text]
        default: []
        }
        let chevron = Text(" › ").foregroundStyle(.tertiary)
        let symbol = control.symbol.map { Text("\(Text(Image(symbol: $0)).foregroundStyle(.secondary)) ") }
        let shown = parts.indices.reduce(Text("")) { line, index in
            var part = Text(parts[index])
            if index == parts.count - 1, let symbol {
                part = Text("\(symbol)\(part)")
            }
            if path ? index == 0 : control.style == "dim" {
                part = part.foregroundStyle(.secondary)
            }
            return index == 0 ? part : Text("\(line)\(chevron)\(part)")
        }
        return (control.digits == "mono" ? shown.monospacedDigit() : shown).fontWeight(.regular).lineLimit(1)
            .truncationMode(.middle)
            .accessibilityValue(parts.joined(separator: " › "))
    }

    @ViewBuilder
    private var openWith: some View {
        if let path = control.value?.text, !path.isEmpty {
            let others = Registry.openers(path, options: true).filter { $0.id != plugin.manifest.id }
            if !page.store.machine.isRemote || !others.isEmpty {
                OpenWith(path: path, apps: !page.store.machine.isRemote, plugins: others, pick: plugin.reopen(as:))
            }
        }
    }
}

private struct HeaderMenu: View {
    let control: PluginManifest.Control
    let header: Header

    var body: some View {
        let items = control.items ?? [], value = control.value?.text
        let picked = items.first { $0.value != nil && $0.value == value }
        let shown = picked?.title ?? control.title ?? "", symbol = picked?.symbol ?? control.symbol
        let sections = sections(items)
        Menu {
            ForEach(sections.indices, id: \.self) { index in
                let (heading, items) = sections[index]
                if let heading {
                    Section(heading) { rows(items, value) }
                } else {
                    rows(items, value)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if control.busy == true {
                    ProgressView().controlSize(.mini)
                } else if let symbol {
                    Image(symbol: symbol)
                }
                if control.style != "icon" {
                    Text(shown).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .help(control.style == "icon" ? shown : "")
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel(control.label ?? control.title ?? "")
        .accessibilityValue(shown)
    }

    private func sections(_ items: [PluginManifest.Item]) -> [(String?, [PluginManifest.Item])] {
        items.reduce(into: [(nil, [])]) { sections, item in
            if item.value == nil, let title = item.title {
                sections.append((title, []))
            } else {
                sections[sections.count - 1].1.append(item)
            }
        }
    }

    @ViewBuilder
    private func label(_ item: PluginManifest.Item, _ pick: String) -> some View {
        if let symbol = item.symbol {
            Label { Text(item.title ?? pick) } icon: { Image(symbol: symbol) }
        } else {
            Text(item.title ?? pick)
        }
    }

    private func rows(_ items: [PluginManifest.Item], _ value: String?) -> some View {
        ForEach(items.indices, id: \.self) { index in
            let item = items[index], id = control.id ?? ""
            if let pick = item.value {
                if pick == value {
                    Toggle(isOn: Binding { true } set: { _ in header.pick(id, .text(pick)) }) { label(item, pick) }
                } else {
                    Button { header.pick(id, .text(pick)) } label: { label(item, pick) }
                }
            } else {
                Divider()
            }
        }
    }
}

private struct OpenWith: View {
    let path: String
    let apps: Bool
    let plugins: [PluginManifest]
    let pick: (PluginManifest) -> Void

    var body: some View {
        let url = URL(filePath: path)
        Group {
            if apps, let main = NSWorkspace.shared.urlForApplication(toOpen: url) {
                Menu {
                    OpenWithItems(url: url, plugins: plugins, pick: pick)
                } label: {
                    HStack(spacing: 4) {
                        Image(nsImage: OpenWithItems.icon(main))
                        Text(FileManager.default.displayName(atPath: main.path)).lineLimit(1)
                    }
                } primaryAction: {
                    NSWorkspace.shared.open([url], withApplicationAt: main,
                                            configuration: NSWorkspace.OpenConfiguration())
                }
                .help("Open with \(FileManager.default.displayName(atPath: main.path))")
            } else {
                Menu("Open With") { OpenWithItems(url: apps ? url : nil, plugins: plugins, pick: pick) }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
    }
}

/// A view of its own: SwiftUI asks LaunchServices again only when the path changes, not at every render of the card.
private struct OpenWithItems: View {
    let url: URL?
    let plugins: [PluginManifest]
    let pick: (PluginManifest) -> Void

    var body: some View {
        if let url {
            let workspace = NSWorkspace.shared, main = workspace.urlForApplication(toOpen: url)
            let others = workspace.urlsForApplications(toOpen: url).filter { $0 != main }
            if let main {
                item(main, url)
                Divider()
            }
            ForEach(others, id: \.self) { item($0, url) }
            if !plugins.isEmpty {
                Divider()
            }
        }
        ForEach(plugins, id: \.id) { plugin in
            Button { pick(plugin) } label: { Label { Text(plugin.name) } icon: { Image(symbol: plugin.icon) } }
        }
    }

    private func item(_ app: URL, _ url: URL) -> some View {
        Button {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } label: {
            Label {
                Text(FileManager.default.displayName(atPath: app.path))
            } icon: {
                Image(nsImage: Self.icon(app))
            }
        }
    }

    /// LaunchServices gives it at 32 pt.
    static func icon(_ app: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
