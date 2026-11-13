import SwiftUI

/// Settings ▸ Keyboard Shortcuts: every action's keys, the app's and each plugin's. A click on the keys records new
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
                    TextField("Search", text: $search, prompt: Text("Search shortcuts"))
                        .labelsHidden().textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("keys.search")
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
                KeyField(keys: keys, recording: recording == hotkey.id) {
                    clash = nil
                    recording = recording == hotkey.id ? nil : hotkey.id
                }
                .accessibilityIdentifier("keys.\(hotkey.id)")
                Button("Reset", systemImage: "arrow.uturn.backward") { hotkeys.set(hotkey, hotkey.keys) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Reset")
                    .opacity(hotkeys.changed(hotkey) ? 1 : 0).disabled(!hotkeys.changed(hotkey))
                    .accessibilityIdentifier("keys.\(hotkey.id).reset")
            }
            if let clash, clash.hotkey.id == hotkey.id {
                HStack(spacing: 8) {
                    Text("\(clash.key.glyphs) is \(clash.other.title)’s key.").foregroundStyle(.secondary)
                        .accessibilityIdentifier("keys.\(hotkey.id).question")
                    Spacer()
                    Button("Cancel") { self.clash = nil }
                    Button("Swap") { swap(clash) }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("keys.\(hotkey.id).swap")
                }
                .controlSize(.small)
            }
        }
        .settingsRow("keys.\(hotkey.id)")
    }

    /// The other action takes this one's first key in place of the one it gives up.
    private func swap(_ clash: Clash) {
        let hotkeys = Hotkeys.shared, old = hotkeys.keys(clash.hotkey).first
        hotkeys.set(clash.other, hotkeys.keys(clash.other).compactMap { $0 == clash.key ? old : $0 })
        hotkeys.set(clash.hotkey, [clash.key])
        self.clash = nil
    }

    /// A monitor sees a key ahead of the menu bar, so ⌘W records instead of closing the window.
    private func listen() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        guard let id = recording else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            MainActor.assumeIsolated { record(event, id) } ? nil : event
        }
    }

    /// True when it took the event.
    private func record(_ event: NSEvent, _ id: String) -> Bool {
        let hotkeys = Hotkeys.shared, plain = event.modifierFlags.isDisjoint(with: [.command, .control, .option])
        guard event.type == .keyDown else {
            recording = nil
            return false
        }
        guard let hotkey = hotkeys.all.first(where: { $0.id == id }) else { return true }
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

/// The action's keys as keycaps, or a prompt while it records.
private struct KeyField: View {
    let keys: [KeyboardShortcut]
    let recording: Bool
    let action: () -> Void

    var body: some View {
        let text = recording ? "Type Shortcut" : keys.map(\.glyphs).joined(separator: " or ")
        Button(action: action) {
            HStack(spacing: 4) {
                if recording {
                    Text("Type Shortcut").foregroundStyle(.tint)
                } else if keys.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                        if index > 0 {
                            Text("or").foregroundStyle(.secondary)
                        }
                        ForEach(key.caps, id: \.self, content: Keycap.init)
                    }
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 4).frame(minWidth: 96, minHeight: 26)
            .background(.quaternary.opacity(recording ? 0.5 : 0), in: .rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7).strokeBorder(recording ? AnyShapeStyle(.tint)
                    : AnyShapeStyle(.quaternary), lineWidth: recording ? 2 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityValue(text)
    }
}
