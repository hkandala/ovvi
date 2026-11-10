import HerdrKit
import SwiftUI

struct FilterList: View {
    struct Item {
        let id: String
        var symbol: String?
        var pane: HostStore.Pane?
        var program: String?
        var state: AgentState?
        let title: String
        var detail = ""
        var keys: [String] = []
        var section: String?
        var note: String?
        var busy = false
        var opens = false
        var button: (title: String, act: () -> Void)?
        var buttonRole: ButtonRole?
        var drop: MenuRowDrop.Target?
        let act: () -> Void
    }

    let prompt: String
    var fieldSymbol: String?
    let name: String
    let items: (String) -> [Item]
    var start = 0
    let maxHeight: CGFloat
    var lit: Binding<String?>?
    var text = ""
    var submit: ((String) -> Void)?
    var typed: ((String) async -> Void)?
    var back: (() -> Void)?
    var rowHeight: CGFloat = 26
    /// AppKit rows (`RowTable`): no `state`, `busy`, `button`, `drop` or `pinned`; `pane`, `program`, `keys` and `note`
    /// show only here.
    var table = false
    /// The last rows sit under the scrolled ones, always in view: macOS 27 takes the workspace menu's New Space as a
    /// drop target only when it is in view as a drag starts.
    var pinned = 0
    var inset: CGFloat = 0
    var autofocus = true
    let done: () -> Void
    @State private var filter = ""
    /// By id: a row that moves or goes must not hand the light, and the row's button, to the row that takes its place.
    @State private var litID: String?
    @State private var rowsHeight: CGFloat = 0
    /// Only a pointer moved since lights a row, not a row that scrolls under a pointer at rest. Not the last hover's
    /// place: a busy app runs a row's hover late, with the pointer already on the next row.
    @State private var pointer = NSEvent.mouseLocation
    @State private var scrolls: Any?
    @State private var pointed = false

    var body: some View {
        let items = items(filter)
        let index = current(items)
        let _ = Latency.shared.filter = filter // swiftlint:disable:this redundant_discardable_let
        VStack(alignment: .leading, spacing: 2) {
            FilterField(prompt: prompt, text: $filter, identifier: "\(name).filter", symbol: fieldSymbol,
                        autofocus: autofocus)
                // Here, not onSubmit: a field's submit action is not refreshed when only the index changes.
                .onKeyPress(.return) {
                    let items = self.items(filter)
                    if let submit {
                        submit(filter)
                        done()
                    } else if !items.isEmpty {
                        act(items[current(items)])
                    }
                    return .handled
                }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                // ⌫ arrives as DEL (U+7F), which `.delete` (U+8) does not match. Not its repeats: holding ⌫ to clear
                // the field must not leave the page.
                .onKeyPress(keys: [.delete, KeyEquivalent("\u{7F}")], phases: .down) { _ in
                    guard filter.isEmpty, let back else { return .ignored }
                    back()
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard let back else { return .ignored }
                    back()
                    return .handled
                }
                .padding(.bottom, 4)
            if submit == nil, table {
                if items.isEmpty, !filter.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "No matches", compact: true)
                        .frame(maxWidth: .infinity).padding(.bottom, inset)
                } else {
                    RowTable(name: name, items: items, lit: index, reveal: pointed ? nil : index, rowHeight: rowHeight,
                             inset: inset, act: act, hover: { item in
                                 guard NSEvent.mouseLocation != pointer else { return }
                                 pointed = true
                                 litID = item.id
                             })
                             .frame(height: min(RowTable.height(items, rowHeight: rowHeight, inset: inset), maxHeight))
                }
            } else if submit == nil {
                ScrollViewReader { proxy in
                    ScrollView {
                        // Lazy: the palette's 100 rows take 230 ms to build and lay out on CI. By place, not by row: a
                        // typed key changes what the rows in view show, instead of making them anew with their
                        // accessibility (100 ms a key at 130 rows with an accessibility client). An Int id inside a row
                        // would catch `scrollTo`.
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(items.enumerated().dropLast(pinned)), id: \.offset) { offset, _ in
                                row(items, offset, index)
                            }
                            if items.count == pinned, !filter.isEmpty {
                                EmptyState(symbol: "magnifyingglass", title: "No matches", compact: true)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.bottom, inset)
                        // Up to the most it shows: a lazy stack's height is a guess that changes as it measures rows,
                        // and each change makes the list again (45 times for one key at 130 rows, 300 ms).
                        .onGeometryChange(for: CGFloat.self) { min($0.size.height, maxHeight) } action: {
                            rowsHeight = $0
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(height: min(rowsHeight, maxHeight))
                    .onChange(of: rowsHeight > 0 ? index : nil) {
                        if !pointed, items.indices.contains(index) {
                            proxy.scrollTo(index, anchor: index == items.count - 1 ? .top : nil)
                        }
                    }
                }
                ForEach(Array(items.enumerated().suffix(pinned)), id: \.element.id) { offset, _ in
                    row(items, offset, index)
                }
            }
        }
        .padding(.bottom, submit == nil ? 0 : inset)
        .onAppear {
            filter = text
            scrolls.map(NSEvent.removeMonitor)
            scrolls = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                MainActor.assumeIsolated {
                    if pointer != NSEvent.mouseLocation {
                        pointer = NSEvent.mouseLocation
                    }
                }
                return event
            }
        }
        .onDisappear {
            scrolls.map(NSEvent.removeMonitor)
            scrolls = nil
        }
        .task(id: filter) { await typed?(filter) }
        .onChange(of: filter) {
            pointed = false
            litID = nil
            pointer = NSEvent.mouseLocation
        }
        .onChange(of: items.isEmpty ? nil : items[index].id, initial: true) { lit?.wrappedValue = $1 }
    }

    /// One view: a header beside its row makes the lazy stack make 5 to 8 times as many rows.
    private func row(_ items: [Item], _ offset: Int, _ index: Int) -> some View {
        let item = items[offset]
        return VStack(alignment: .leading, spacing: 2) {
            if item.section != (offset > 0 ? items[offset - 1].section : nil) {
                if let section = item.section, !section.isEmpty {
                    Text(section).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.top, offset > 0 ? 6 : 0)
                        .accessibilityIdentifier("\(name).section.\(section)")
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Divider().padding(4)
                }
            }
            Button { act(item) } label: {
                MenuRow(item: item, selected: offset == index, height: rowHeight)
            }
            .buttonStyle(ChromeStyle(selected: offset == index, tint: .accentColor))
            .accessibilityIdentifier("\(name).\(item.id)")
            .accessibilityValue(item.state?.word ?? "")
            .accessibilityAddTraits(offset == index ? .isSelected : [])
            // After the row's accessibility, which would name this button too.
            .overlay(alignment: .trailing) {
                if let button = item.button, offset == index, !item.busy {
                    Button(button.title, role: item.buttonRole, action: button.act)
                        .buttonStyle(RowButtonStyle())
                        .padding(.trailing, 4)
                        .accessibilityIdentifier("\(name).\(item.id).\(button.title.lowercased())")
                }
            }
            .modifier(MenuRowDrop(target: item.drop))
            .onContinuousHover { phase in
                guard case .active = phase, NSEvent.mouseLocation != pointer else { return }
                pointed = true
                litID = item.id
            }
        }
    }

    private func current(_ items: [Item]) -> Int {
        items.firstIndex { $0.id == litID } ?? max(0, min(filter.isEmpty ? start : 0, items.count - 1))
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let items = items(filter)
        pointed = false
        pointer = NSEvent.mouseLocation
        if !items.isEmpty {
            let item = items[max(0, min(current(items) + step, items.count - 1))]
            litID = item.id
            // The keyboard stays in the field, so VoiceOver would not say the new row.
            AccessibilityNotification.Announcement(item.title).post()
        }
        return .handled
    }

    private func act(_ item: Item) {
        item.act()
        if !item.opens {
            done()
        }
    }
}

/// Plain text until clicked (or with `autofocus`), so the window has no text field to hand the keyboard to at launch;
/// keys belong to the panes.
struct FilterField: View {
    let prompt: String
    @Binding var text: String
    let identifier: String
    var symbol: String?
    var autofocus = false
    var focus = 0
    var trailing: CGFloat = 0
    @State private var editing = false
    @FocusState private var focused: Bool
    static let panelKeysTaken = Notification.Name("dev.ovvi.panelKeysTaken")

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol ?? "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if editing || autofocus || !text.isEmpty {
                TextField(prompt, text: $text)
                    .focused($focused)
                    .focusSoon($focused, editing || autofocus)
                    .onChange(of: focused) { editing = focused }
                    .accessibilityIdentifier(identifier)
            } else {
                Button { editing = true } label: {
                    Text(prompt).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier)
            }
        }
        .padding(.trailing, trailing)
        .fieldCapsule()
        .contentShape(.capsule)
        .onTapGesture { editing = true }
        .onChange(of: focus) {
            editing = true
            // A first responder set during an update is undone.
            DispatchQueue.main.async { focused = true }
        }
        .task(id: autofocus) {
            guard autofocus else { return }
            for await _ in NotificationCenter.default.notifications(named: Self.panelKeysTaken).map({ _ in () }) {
                focused = true
            }
        }
    }
}

struct RenameField: View {
    let prompt: String
    let initial: String
    let commit: (String) -> Void
    let end: () -> Void
    var blur: (() -> Void)?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $draft).textFieldStyle(.plain).focused($focused)
            .blursWhenHidden($focused)
            .onSubmit {
                commit(draft)
                end()
            }
            .onExitCommand(perform: end)
            .onChange(of: focused) { _, now in
                if !now {
                    (blur ?? end)()
                }
            }
            .onAppear { draft = initial }
            .focusSoon($focused)
    }
}

extension View {
    func fieldCapsule(fill: Bool = true) -> some View {
        modifier(FieldCapsule(fill: fill))
    }

    func focusSoon(_ focused: FocusState<Bool>.Binding, _ asks: Bool = true) -> some View {
        task(id: asks) {
            guard asks else { return }
            // ponytail: focus asked for as the field appears is dropped (AppKit has not made it a key view yet), and a
            // single later ask is sometimes dropped too; ask every 50 ms until it holds, for up to 1 s.
            // Upgrade: an AppKit field that takes first responder in viewDidMoveToWindow.
            for _ in 0 ..< 20 where !focused.wrappedValue {
                try? await Task.sleep(for: .milliseconds(50))
                focused.wrappedValue = true
            }
        }
    }
}

private struct FieldCapsule: ViewModifier {
    let fill: Bool
    @Environment(\.controlSize) private var size
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        let large = size == .large
        let shape = large ? AnyShape(.panel) : AnyShape(.capsule)
        content.textFieldStyle(.plain).transformEnvironment(\.font) { font in font = large ? .system(size: 15) : font }
            .padding(.horizontal, large ? 12 : 8).padding(.vertical, large ? 9 : 5)
            .background(fill ? large ? AnyShapeStyle(look.paletteField) : AnyShapeStyle(.primary.opacity(0.07))
                : AnyShapeStyle(.clear), in: shape)
    }
}

extension String {
    func matches(_ filter: String) -> Bool {
        let filter = filter.trimmingCharacters(in: .whitespaces)
        return filter.isEmpty || localizedStandardContains(filter)
    }
}
