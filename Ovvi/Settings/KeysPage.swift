import SwiftUI

/// Settings ▸ Shortcuts: every action's keys, the app's and each plugin's. A click on the keys records new
/// ones: ⎋ cancels, ⌫ clears, a key another action has asks first.
struct KeysPage: View {
    @State private var search = ""
    @State private var recording: String?
    @State private var clash: Clash?
    @State private var monitor: Any?
    @Environment(\.look) private var look

    struct Clash {
        let hotkey: Hotkey, key: KeyboardShortcut, other: Hotkey
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
        Form {
            Section {
                HStack(spacing: 8) {
                    FilterField(prompt: "Search", text: $search, identifier: "keys.search", symbol: "magnifyingglass")
                        .labelsHidden()
                    Button("Reset All") { hotkeys.resetAll() }.disabled(hotkeys.saved.isEmpty)
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
                        row(hotkey, all)
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
    }

    private func row(_ hotkey: Hotkey, _ all: [Hotkey]) -> some View {
        let hotkeys = Hotkeys.shared, keys = hotkeys.keys(hotkey)
        let taken = keys.lazy.compactMap { hotkeys.clash($0, for: hotkey, in: all) }.first
        let asking = clash.flatMap { $0.hotkey.id == hotkey.id ? $0 : nil }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(hotkey.title)
                if let taken {
                    let note = "\(taken.title) has this key too"
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(look.needsYou)
                        .help(note).accessibilityLabel(note)
                        .accessibilityIdentifier("keys.\(hotkey.id).clash")
                }
                Spacer(minLength: 12)
                KeyField(keys: keys, recording: recording == hotkey.id, asking: asking?.key) {
                    clash = nil
                    recording = hotkey.id
                }
                .accessibilityIdentifier("keys.\(hotkey.id)")
                Button("Reset", systemImage: "arrow.uturn.backward") { hotkeys.set(hotkey, hotkey.keys) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Reset").frame(width: Self.reset)
                    .opacity(hotkeys.changed(hotkey) ? 1 : 0).disabled(!hotkeys.changed(hotkey))
                    .accessibilityIdentifier("keys.\(hotkey.id).reset")
            }
            if let asking {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(look.needsYou)
                        Text("\(asking.key.glyphs) is \(asking.other.title)’s key.").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .accessibilityIdentifier("keys.\(hotkey.id).question")
                    Spacer(minLength: 8)
                    Button("Cancel") { clash = nil }
                    if !Hotkeys.fixed.contains(where: { $0.id == asking.other.id }) {
                        Button("Swap") { swap(asking) }.buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("keys.\(hotkey.id).swap")
                    }
                }
                .controlSize(.small)
                // The buttons end where the key field ends, left of the reset button.
                .padding(.trailing, Self.reset + 8)
            }
        }
    }

    private static let reset: CGFloat = 16

    /// The other action takes this one's first key in place of the one it gives up.
    private func swap(_ clash: Clash) {
        let hotkeys = Hotkeys.shared, old = hotkeys.keys(clash.hotkey).first
        hotkeys.set(clash.other, hotkeys.keys(clash.other).compactMap { $0 == clash.key ? old : $0 })
        hotkeys.set(clash.hotkey, [clash.key])
        self.clash = nil
    }

    /// A monitor sees a key ahead of the menu bar, so ⌘W records instead of closing the window. A click ends the
    /// recording and does nothing else, so a click on the field stops it too.
    private func listen() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        guard let id = recording, let window = NSApp.keyWindow else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            MainActor.assumeIsolated { record(event, id, in: window) } ? nil : event
        }
    }

    /// True when it took the event.
    private func record(_ event: NSEvent, _ id: String, in window: NSWindow) -> Bool {
        let hotkeys = Hotkeys.shared, plain = event.modifierFlags.isDisjoint(with: [.command, .control, .option])
        guard event.window === window, event.type == .keyDown,
              let hotkey = hotkeys.all.first(where: { $0.id == id })
        else {
            recording = nil
            return event.window === window
        }
        if plain, event.specialKey == .delete || event.specialKey == .deleteForward {
            hotkeys.set(hotkey, [])
        } else if plain, event.charactersIgnoringModifiers == "\u{1B}" {
            // Esc: no change.
        } else if let key = KeyboardShortcut(event: event) {
            if let other = hotkeys.clash(key, for: hotkey) {
                clash = Clash(hotkey: hotkey, key: key, other: other)
            } else {
                hotkeys.set(hotkey, [key])
            }
        } else {
            NSSound.beep()
            return true
        }
        recording = nil
        return true
    }
}

/// The action's keys, comma separated, in a field of one size for every row: accent ringed while it records, ringed
/// as a warning with the key it asks about.
private struct KeyField: View {
    let keys: [KeyboardShortcut]
    let recording: Bool
    let asking: KeyboardShortcut?
    let action: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        let shown = asking.map { [$0] } ?? keys, plain = recording || shown.isEmpty
        let text = recording ? "Type shortcut…" : shown.isEmpty ? "None" : shown.map(\.glyphs).joined(separator: ", ")
        let ring = recording ? Color.accentColor : asking == nil ? nil : look.needsYou
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button(action: action) {
            Text(text).tracking(plain ? 0 : 1)
                .foregroundStyle(plain ? .secondary : .primary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
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
        .accessibilityLabel(text)
        .accessibilityValue(text)
    }
}
