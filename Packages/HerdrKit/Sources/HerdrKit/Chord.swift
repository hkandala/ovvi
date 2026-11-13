/// A keyboard shortcut as text, in a plugin's manifest and in the app's saved keys: `cmd+shift+k`, `ctrl+tab`,
/// `option+left`. It needs ⌘, ⌃ or ⌥: a key with only ⇧ or none types into a text field.
public struct Chord: Hashable, Sendable, CustomStringConvertible {
    /// In the order the Mac draws them: ⌃⌥⇧⌘.
    public static let modifierNames = ["ctrl", "option", "shift", "cmd"]
    public static let keyNames: Set = ["left", "right", "up", "down", "return", "tab", "space", "escape", "delete",
                                       "plus"]
    private static let aliases = ["control": "ctrl", "alt": "option", "opt": "option", "command": "cmd",
                                  "esc": "escape", "enter": "return", "backspace": "delete", "+": "plus"]

    public let modifiers: Set<String>
    /// One character, lowercased, or one of `keyNames`.
    public let key: String

    public init?(modifiers: Set<String>, key: String) {
        let key = Self.aliases[key.lowercased()] ?? key.lowercased()
        guard modifiers.isSubset(of: Self.modifierNames), !modifiers.isDisjoint(with: ["cmd", "ctrl", "option"]),
              Self.keyNames.contains(key) || key.count == 1 && key != " " else { return nil }
        (self.modifiers, self.key) = (modifiers, key)
    }

    public init?(_ text: String) {
        var parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // `cmd++`: the key is the plus.
        if parts.count > 2, parts.suffix(2) == ["", ""] {
            parts = parts.dropLast(2) + ["+"]
        }
        guard let key = parts.popLast() else { return nil }
        let modifiers = parts.map { Self.aliases[$0] ?? $0 }
        guard Set(modifiers).count == modifiers.count else { return nil }
        self.init(modifiers: Set(modifiers), key: key)
    }

    public var description: String {
        (Self.modifierNames.filter(modifiers.contains) + [key]).joined(separator: "+")
    }
}
