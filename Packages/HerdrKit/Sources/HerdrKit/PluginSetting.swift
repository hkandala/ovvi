import Foundation

public struct PluginSetting: Decodable, Sendable, Equatable {
    public let id: String
    public let type: String
    public let title: String
    public let `default`: Value
    public var description: String?
    public var section: String?
    public var options: [Option]?
    public var min: Double?, max: Double?, step: Double?
    public var unit: String?
    public var placeholder: String?
    public var kind: String?

    public struct Option: Decodable, Sendable, Equatable {
        public let value: String
        public let title: String

        public init(value: String, title: String) {
            (self.value, self.title) = (value, title)
        }
    }

    public enum Value: Decodable, Sendable, Hashable {
        case bool(Bool), number(Double), text(String)

        public init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let bool = try? value.decode(Bool.self) {
                self = .bool(bool)
            } else if let number = try? value.decode(Double.self) {
                self = .number(number)
            } else {
                self = try .text(value.decode(String.self))
            }
        }

        public init?(json: Any) {
            if let number = json as? NSNumber {
                // A JSON boolean is an NSNumber too.
                self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number
                    .doubleValue)
            } else if let text = json as? String {
                self = .text(text)
            } else {
                return nil
            }
        }

        public var json: Any {
            switch self {
            case let .bool(bool): bool
            case let .number(number): number
            case let .text(text): text
            }
        }
    }

    public init(id: String, type: String, title: String, default value: Value, description: String?,
                options: [Option]?)
    {
        (self.id, self.type, self.title, self.default) = (id, type, title, value)
        (self.description, self.options) = (description, options)
    }

    public func fits(_ value: Value) -> Bool {
        switch (type, value) {
        case (_, .bool): type == "toggle"
        case let ("choice", .text(text)): options?.contains { $0.value == text } == true
        case let ("number", .number(number)): number.isFinite && number >= min ?? -.infinity
            && number <= max ?? .infinity
        case let ("text", .text(text)): text.utf8.count <= 1024
        case let ("path", .text(text)): text.isEmpty || text.hasPrefix("/") || text == "~" || text.hasPrefix("~/")
        default: false
        }
    }

    func check(_ bad: (String, String) -> ManifestError) throws(ManifestError) {
        guard PluginManifest.isID(id) else { throw bad("id", PluginManifest.idRule) }
        guard ["toggle", "choice", "number", "text", "path"].contains(type) else {
            throw bad("type", "must be toggle, choice, number, text or path")
        }
        let lengths = [("title", title, 1 ... 60), ("section", section ?? "", 0 ... 60),
                       ("description", description ?? "", 0 ... 200)]
        for (field, text, range) in lengths where !range.contains(text.count) {
            throw bad(field, "must be \(range.lowerBound) to \(range.upperBound) characters")
        }
        if type == "choice" {
            let values = Set((options ?? []).map(\.value))
            guard (2 ... 12).contains(options?.count ?? 0), values.count == options?.count,
                  options?.allSatisfy({ !$0.title.isEmpty }) == true
            else { throw bad("options", "must be 2 to 12 options, each with its own value and a title") }
        }
        guard min ?? -.infinity < max ?? .infinity, step ?? 1 > 0 else {
            throw bad("min", "must be under max, and step over 0")
        }
        guard (placeholder ?? "").utf8.count <= 1024 else { throw bad("placeholder", "is over 1 KB") }
        guard kind.map(["file", "folder"].contains) != false else { throw bad("kind", "must be file or folder") }
        guard fits(self.default) else { throw bad("default", "does not fit the type, options or range") }
    }
}

extension PluginManifest {
    static func check(settings: [PluginSetting], _ bad: (String, String) -> ManifestError) throws(ManifestError) {
        guard settings.count <= 16 else { throw bad("settings", "has over 16 settings") }
        var ids = Set<String>()
        for (index, setting) in settings.enumerated() {
            try setting.check { bad("settings.\(index).\($0)", $1) }
            guard ids.insert(setting.id).inserted else { throw bad("settings.\(index).id", "is taken") }
        }
    }
}
