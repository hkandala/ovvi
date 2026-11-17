import SwiftUI

/// Settings ▸ Shortcuts: every action's keys, the app's and each plugin's, one field each. A click on a field records
/// a new key: ⎋ cancels, ⌫ or the field's × removes that key, a key another action has asks first. ⊕ adds a field.
struct KeysPage: View {
    @State private var search = ""
    @State private var recording: Slot?
    /// Kept after the question closes, so its words stay while it fades.
    @State private var clash: Clash?
    @State private var asking = false
    /// The recording field's ×, in the window: the monitor lets a click on it through.
    @State private var remove: (slot: Slot, frame: CGRect)?
    @State private var monitor: Any?
    @Environment(\.look) private var look

    /// One of an action's keys; the index past its last key is a new one.
    struct Slot: Equatable {
        let id: String, index: Int
    }

    /// `old`: the key that the new one replaces, none for an added key.
    struct Clash {
        let hotkey: Hotkey, key: KeyboardShortcut, other: Hotkey, index: Int, old: KeyboardShortcut?
        var fixed: Bool {
            Hotkeys.fixed.contains { $0.id == other.id }
        }
    }

    var body: some View {
        let hotkeys = Hotkeys.shared, all = hotkeys.all
        let typed = search.lowercased().split(separator: " ")
        let shown = all.filter { hotkey in
            let words = "\(hotkey.title) \(hotkey.group) "
                + hotkeys.keys(hotkey).map { "\($0.glyphs) \($0.chord)" }.joined(separator: " ")
            return typed.allSatisfy(words.lowercased().contains)
        }
        let groups = (Hotkeys.groups + all.map(\.group)).reduce(into: [String]()) { groups, group in
            if !groups.contains(group), shown.contains(where: { $0.group == group }) {
                groups.append(group)
            }
        }
        let question = clash.map { "\($0.key.glyphs) is \($0.other.title)’s key." } ?? ""
        Form {
            Section {
                HStack(spacing: 8) {
                    FilterField(prompt: "Search", text: $search, identifier: "keys.search", symbol: "magnifyingglass")
                        .labelsHidden()
                    Button("Reset All") {
                        hotkeys.resetAll()
                    }.disabled(hotkeys.saved.isEmpty)
                        .accessibilityIdentifier("keys.reset-all")
                }
                .settingsRow("keys.search")
            }
            if let failure = PluginInstalls.shared.failure {
                NoticeCapsule(tone: .error, text: failure.text) {}.frame(maxWidth: .infinity)
            }
            ForEach(groups, id: \.self) { group in
                Section(group) {
                    ForEach(shown.filter { $0.group == group }) { hotkey in
                        // A row of its own: the pointer over it runs only its body.
                        Hovering { row(hotkey, all, hovered: $0) }
                    }
                }
            }
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .onChange(of: recording) { listen() }
        .onDisappear {
            recording = nil
            listen()
        }
        .alert(question, isPresented: $asking, presenting: clash) { clash in
            if clash.fixed {
                Button("OK", role: .cancel) {}
            } else {
                Button("Cancel", role: .cancel) {}
                Button(clash.old == nil ? "Use Here" : "Swap") { take(clash) }.keyboardShortcut(.defaultAction)
            }
        } message: { clash in
            Text(clash.fixed ? "macOS keeps it."
                : clash.old.map { "\(clash.other.title) gets \($0.glyphs) in its place." }
                ?? "\(clash.other.title) loses it.")
        }
    }

    private func row(_ hotkey: Hotkey, _ all: [Hotkey], hovered: Bool) -> some View {
        let hotkeys = Hotkeys.shared, keys = hotkeys.keys(hotkey)
        let taken = keys.lazy.compactMap { hotkeys.clash($0, for: hotkey, in: all) }.first
        let recorded = recording?.id == hotkey.id ? recording?.index : nil
        let asked = asking && clash?.hotkey.id == hotkey.id ? clash : nil
        // The asked key in its field, a new field while one records or asks, None for no key.
        var shown = keys.map(Optional.some)
        if let asked {
            if asked.index < shown.count {
                shown[asked.index] = asked.key
            } else {
                shown.append(asked.key)
            }
        }
        if recorded == shown.count || shown.isEmpty {
            shown.append(nil)
        }
        return HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 8) {
                Text(hotkey.title)
                if let taken {
                    let note = "\(taken.title) has this key too"
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(look.needsYou)
                        .help(note).accessibilityLabel(note)
                        .accessibilityIdentifier("keys.\(hotkey.id).clash")
                }
            }
            .frame(height: 24)
            Spacer(minLength: 12)
            fields(hotkey, shown, recorded: recorded, asked: asked, hovered: hovered)
        }
    }

    /// The key fields, stacked, with the reset button before the first and ⊕ before the last.
    private func fields(_ hotkey: Hotkey, _ shown: [KeyboardShortcut?], recorded: Int?,
                        asked: Clash?, hovered: Bool) -> some View
    {
        let hotkeys = Hotkeys.shared, changed = hotkeys.changed(hotkey), keys = hotkeys.keys(hotkey)
        let adds = hovered && recorded == nil && asked == nil && !keys.isEmpty
        let add = { recording = Slot(id: hotkey.id, index: keys.count) }
        return VStack(alignment: .trailing, spacing: 6) {
            ForEach(shown.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    // Before the fields, so every field ends at the row's edge.
                    if index == 0 {
                        Button("Reset", systemImage: "arrow.uturn.backward") { hotkeys.set(hotkey, hotkey.keys) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).help("Reset")
                            .opacity(changed ? 1 : 0).disabled(!changed).accessibilityHidden(!changed)
                            .accessibilityIdentifier("keys.\(hotkey.id).reset")
                    }
                    let last = adds && index == shown.count - 1
                    Button("Add Shortcut", systemImage: "plus.circle", action: add)
                        .labelStyle(.iconOnly).buttonStyle(.borderless).help("Add Shortcut")
                        .opacity(last ? 1 : 0).disabled(!last).accessibilityHidden(!last)
                        .accessibilityIdentifier("keys.\(hotkey.id).add")
                    let slot = Slot(id: hotkey.id, index: index)
                    KeyField(id: "keys.\(hotkey.id)", index: index, title: hotkey.title, key: shown[index],
                             recording: recorded == index, asked: asked?.index == index, add: add,
                             action: { recording = slot },
                             remove: {
                                 drop(index, of: hotkey)
                                 recording = nil
                             },
                             removeAt: { remove = (slot, $0) })
                }
            }
        }
    }

    /// Swap: the other action takes the key this one gives up. Use Here: the other action loses it.
    private func take(_ clash: Clash) {
        let hotkeys = Hotkeys.shared
        hotkeys.set(clash.other, hotkeys.keys(clash.other).compactMap { $0.runs(clash.key) ? clash.old : $0 })
        put(clash.key, at: clash.index, of: clash.hotkey)
    }

    private func drop(_ index: Int, of hotkey: Hotkey) {
        var keys = Hotkeys.shared.keys(hotkey)
        if keys.indices.contains(index) {
            keys.remove(at: index)
            Hotkeys.shared.set(hotkey, keys)
        }
    }

    private func put(_ key: KeyboardShortcut, at index: Int, of hotkey: Hotkey) {
        var keys = Hotkeys.shared.keys(hotkey)
        if index < keys.count {
            keys[index] = key
        } else {
            keys.append(key)
        }
        Hotkeys.shared.set(hotkey, keys)
    }

    /// A monitor sees a key ahead of the menu bar, so ⌘W records instead of closing the window. A click ends the
    /// recording and does nothing else, so a click on the field stops it too; only the field's × takes its click.
    private func listen() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        guard let slot = recording, let window = NSApp.keyWindow else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            MainActor.assumeIsolated { record(event, slot, in: window) } ? nil : event
        }
    }

    /// True when it took the event.
    private func record(_ event: NSEvent, _ slot: Slot, in window: NSWindow) -> Bool {
        let hotkeys = Hotkeys.shared, plain = event.modifierFlags.isDisjoint(with: [.command, .control, .option])
        guard event.window === window, event.type == .keyDown,
              let hotkey = hotkeys.all.first(where: { $0.id == slot.id })
        else {
            if event.window === window, let remove, remove.slot == slot, let view = window.contentView {
                var point = view.convert(event.locationInWindow, from: nil)
                point.y = view.isFlipped ? point.y : view.bounds.height - point.y
                if remove.frame.contains(point) {
                    return false
                }
            }
            recording = nil
            return event.window === window
        }
        let keys = hotkeys.keys(hotkey)
        if plain, event.specialKey == .delete || event.specialKey == .deleteForward {
            drop(slot.index, of: hotkey)
        } else if plain, event.charactersIgnoringModifiers == "\u{1B}" {
            // Esc: no change.
        } else if let key = KeyboardShortcut(event: event) {
            if keys.contains(where: { $0.runs(key) }) {
                // This action's key already.
            } else if let other = hotkeys.clash(key, for: hotkey) {
                clash = Clash(hotkey: hotkey, key: key, other: other, index: slot.index,
                              old: keys.indices.contains(slot.index) ? keys[slot.index] : nil)
                asking = true
            } else {
                put(key, at: slot.index, of: hotkey)
            }
        } else {
            NSSound.beep()
            return true
        }
        recording = nil
        return true
    }
}

/// One key in a field of one size for every row: accent ringed while it records, with an × that removes the key it
/// had; ringed as a warning while it asks about its key.
private struct KeyField: View {
    /// The first field's is the action's; the others' end in their index.
    let id: String, index: Int
    let title: String
    let key: KeyboardShortcut?
    let recording: Bool
    let asked: Bool
    let add: () -> Void
    let action: () -> Void
    let remove: () -> Void
    /// Where the ×, which the key monitor would take, is in the window.
    let removeAt: (CGRect) -> Void
    @Environment(\.look) private var look

    var body: some View {
        let removes = recording && key != nil
        let text = recording ? "Type shortcut…" : key?.glyphs ?? "None", plain = recording || key == nil
        let ring = recording ? Color.accentColor : asked ? look.needsYou : nil
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button(action: action) {
            Text(text).tracking(plain ? 0 : 1)
                .foregroundStyle(plain ? .secondary : .primary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.leading, 8).padding(.trailing, removes ? 22 : 8)
                .frame(width: 128, height: 24)
                .background(.quaternary.opacity(0.5), in: shape)
                .overlay {
                    if let ring {
                        shape.strokeBorder(ring, lineWidth: 2)
                    } else {
                        shape.strokeBorder(.separator)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(index == 0 ? title : "\(title), shortcut \(index + 1)")
        .accessibilityValue(text)
        .accessibilityIdentifier(index == 0 ? id : "\(id).\(index)")
        .accessibilityAction(named: "Add Shortcut", add)
        .overlay(alignment: .trailing) {
            if removes {
                Button("Remove Shortcut", systemImage: "xmark.circle.fill", action: remove)
                    .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove Shortcut")
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { removeAt($0) }
                    .onDisappear { removeAt(.null) }
                    .padding(.trailing, 5)
                    .accessibilityIdentifier("\(id).remove")
            }
        }
    }
}

/// Whether the pointer is over the content.
private struct Hovering<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovered = false

    var body: some View {
        content(hovered).contentShape(Rectangle()).onContinuousHover { phase in
            if case .active = phase {
                hovered = true
            } else {
                hovered = false
            }
        }
    }
}
