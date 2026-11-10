import Foundation
import UniformTypeIdentifiers

public struct PluginManifest: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let api: Int
    public let entry: String?
    public let icon: String
    public let description: String
    public let keywords: [String]
    public let opens: Opens
    public let chooser: String?
    public let header: [Control]
    public let history: Bool
    public let commands: [Command]
    public let handles: [String]
    public let settings: [PluginSetting]

    public struct Opens: Decodable, Sendable, Equatable {
        public var files: [String] = []
        public var folders = false
        public var git = false
        public var urls: [String] = []
        public var priority = "default"

        public init(urls: [String] = []) {
            self.urls = urls
        }

        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: OpensKeys.self)
            files = try values.decodeIfPresent([String].self, forKey: .files) ?? []
            folders = try values.decodeIfPresent(Bool.self, forKey: .folders) ?? false
            git = try values.decodeIfPresent(Bool.self, forKey: .git) ?? false
            urls = try values.decodeIfPresent([String].self, forKey: .urls) ?? []
            priority = try values.decodeIfPresent(String.self, forKey: .priority) ?? "default"
        }
    }

    public struct Control: Decodable, Sendable, Equatable {
        public let type: String
        public let id: String?
        public var symbol: String?
        public var title: String?
        public var label: String?
        public var value: Value?
        public var options: [Item]?
        public var items: [Item]?
        public var placeholder: String?
        public var style: String?
        public var digits: String?
        public var gap: Double?
        public var hidden: Bool?
        public var enabled: Bool?
        public var badge: String?
        public var busy: Bool?
    }

    public enum Value: Decodable, Sendable, Equatable {
        case bool(Bool), text(String), list([String])

        public init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let bool = try? value.decode(Bool.self) {
                self = .bool(bool)
            } else if let list = try? value.decode([String].self) {
                self = .list(list)
            } else {
                self = try .text(value.decode(String.self))
            }
        }
    }

    public struct Item: Decodable, Sendable, Equatable {
        public let value: String?
        public let title: String?
        public let symbol: String?

        public init(from decoder: any Decoder) throws {
            if let divider = try? decoder.singleValueContainer().decode(String.self), divider == "-" {
                (value, title, symbol) = (nil, nil, nil)
                return
            }
            let values = try decoder.container(keyedBy: ItemKeys.self)
            value = try values.decodeIfPresent(String.self, forKey: .value)
            title = try values.decode(String.self, forKey: .title)
            symbol = try values.decodeIfPresent(String.self, forKey: .symbol)
        }
    }

    public struct Command: Decodable, Sendable, Equatable {
        public let id: String
        public let title: String
        public let menu: String?
        public let key: String?
        public let symbol: String?
        public let checked: Bool?
        public let keywords: [String]?
    }

    public init(id: String, name: String, icon: String, description: String, keywords: [String], opens: Opens,
                chooser: String?, settings: [PluginSetting])
    {
        self.settings = settings
        (self.id, self.name, version, api, entry, self.icon) = (id, name, "1.0.0", 1, nil, icon)
        (self.description, self.keywords, self.opens, self.chooser) = (description, keywords, opens, chooser)
        (header, history, commands, handles) = ([], false, [], [])
    }

    /// The runtime imports it by this name, and its CSS shares the name.
    public var entryName: String {
        (((entry ?? "") as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    public init(package data: Data) throws(ManifestError) {
        do {
            self = try JSONDecoder().decode(Self.self, from: data)
        } catch let error as ManifestError {
            throw error
        } catch let DecodingError.keyNotFound(key, context) {
            throw ManifestError(field: context.codingPath + [key], "is missing")
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            throw ManifestError(field: context.codingPath, "has the wrong type")
        } catch let DecodingError.dataCorrupted(context) where !context.codingPath.isEmpty {
            throw ManifestError(field: context.codingPath, "has the wrong type")
        } catch {
            throw ManifestError(text: "is not JSON")
        }
    }

    public init(from decoder: any Decoder) throws {
        let package = try decoder.container(keyedBy: PackageKeys.self)
        version = try package.decode(String.self, forKey: .version)
        description = try package.decodeIfPresent(String.self, forKey: .description) ?? ""
        keywords = try package.decodeIfPresent([String].self, forKey: .keywords) ?? []
        let values = try package.nestedContainer(keyedBy: Keys.self, forKey: .ovvi)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        api = try values.decode(Int.self, forKey: .api)
        entry = try values.decode(String.self, forKey: .entry)
        icon = try values.decode(String.self, forKey: .icon)
        opens = try values.decodeIfPresent(Opens.self, forKey: .opens) ?? Opens()
        chooser = try values.decodeIfPresent(String.self, forKey: .chooser)
        header = try values.decodeIfPresent([Control].self, forKey: .header) ?? []
        history = try values.decodeIfPresent(Bool.self, forKey: .history) ?? false
        commands = try values.decodeIfPresent([Command].self, forKey: .commands) ?? []
        handles = try values.decodeIfPresent([String].self, forKey: .handles) ?? []
        settings = try values.decodeIfPresent([PluginSetting].self, forKey: .settings) ?? []
        try check(values.codingPath)
    }

    private enum PackageKeys: String, CodingKey {
        case version, description, keywords, ovvi
    }

    private enum Keys: String, CodingKey {
        case id, name, api, entry, icon, opens, chooser, header, history, commands, handles, settings
    }

    static func isID(_ id: some StringProtocol) -> Bool {
        let low = { (char: Character) in char.isASCII && (char.isLowercase || char.isNumber) }
        return (1 ... 64).contains(id.count) && id.first.map(low) == true && id.allSatisfy { low($0) || $0 == "-" }
    }

    static let idRule = "must be 1 to 64 of a-z, 0-9 and -, starting with a letter or digit"

    private func check(_ path: [any CodingKey]) throws {
        func bad(_ field: String, _ text: String) -> ManifestError {
            ManifestError(text: (path.map(\.stringValue) + [field]).joined(separator: ".") + " " + text)
        }
        guard PluginManifest.isID(id) else { throw bad("id", PluginManifest.idRule) }
        guard !name.isEmpty, !icon.isEmpty else { throw bad(name.isEmpty ? "name" : "icon", "is empty") }
        guard api >= 1 else { throw bad("api", "must be 1 or more") }
        let file = entry ?? ""
        guard (file as NSString).pathExtension == "js", !file.hasPrefix("/"), !file.split(separator: "/").contains("..")
        else { throw bad("entry", "must be a built .js file in the package") }
        guard ["default", "option"].contains(opens.priority) else {
            throw bad("opens.priority", "must be default or option")
        }
        // A file or an address needs a path the chooser has not got.
        guard chooser == nil || opens.files.isEmpty && opens.urls.isEmpty || opens.folders || opens.git else {
            throw bad("chooser", "needs opens with folders or git, or no opens")
        }
        try checkControls(bad)
        try Self.check(settings: settings, bad)
    }

    private func checkControls(_ bad: (String, String) -> ManifestError) throws {
        let controls = ["button", "toggle", "segmented", "menu", "field", "text", "spacer", "openWith"]
        var ids = Set<String>()
        for control in header {
            guard controls.contains(control.type) else { throw bad("header", "has an unknown type \(control.type)") }
            guard control.type == "spacer" || control.id.map({ ids.insert($0).inserted }) == true else {
                throw bad("header", "needs a unique id on each \(control.type)")
            }
            // A segmented option without a value would show as picked while nothing is.
            guard control.gap ?? 0 >= 0, control.digits ?? "mono" == "mono",
                  control.options?.allSatisfy({ $0.value != nil }) != false
            else {
                throw bad("header", "has a bad gap, digits or option on \(control.id ?? "")")
            }
        }
        for command in commands {
            guard ids.insert(command.id).inserted else { throw bad("commands", "has the id \(command.id) twice") }
            guard command.menu.map(["file", "edit", "view"].contains) != false else {
                throw bad("commands", "menu must be file, edit or view")
            }
            guard command.key.map({ $0.hasPrefix("cmd+") && $0.count > 4 }) != false else {
                throw bad("commands", "key must be a ⌘ chord such as cmd+e")
            }
        }
        if let handle = handles.first(where: { !["save", "find"].contains($0) }) {
            throw bad("handles", "has an unknown command \(handle)")
        }
    }

    /// By the name alone, so a remote file is not read first. A name the system does not know (`.rs`) matches no type.
    public func rank(file path: String) -> Int? {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let type = ext.isEmpty ? nil : UTType(filenameExtension: ext).flatMap { $0.isDynamic ? nil : $0 }
        return opens.files.compactMap { pattern -> Int? in
            if pattern == "*" {
                return 0
            }
            if !pattern.contains("*"), let wanted = UTType(pattern) {
                // More supertypes: a more specific type.
                return type?.conforms(to: wanted) == true ? 100 + wanted.supertypes.count : nil
            }
            guard fnmatch(pattern, name, FNM_CASEFOLD) == 0 else { return nil }
            return pattern.contains(where: { "*?[".contains($0) }) ? 900 : 1000
        }.max()
    }

    public func opens(url: String) -> Bool {
        opens.urls.contains { fnmatch($0, url, FNM_CASEFOLD) == 0 }
    }
}

private enum OpensKeys: String, CodingKey {
    case files, folders, git, urls, priority
}

private enum ItemKeys: String, CodingKey {
    case value, title, symbol
}

public struct ManifestError: Error, Equatable, CustomStringConvertible {
    public let text: String

    init(text: String) {
        self.text = text
    }

    init(field path: [any CodingKey], _ text: String) {
        self.text = path.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".") + " " + text
    }

    public var description: String {
        text
    }
}

public extension PluginManifest.Value {
    init?(json: Any) {
        // A JSON number is an NSNumber too: only a real boolean is one.
        if let number = json as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            self = .bool(number.boolValue)
        } else if let list = json as? [String] {
            self = .list(list)
        } else if let text = json as? String {
            self = .text(text)
        } else {
            return nil
        }
    }

    var json: Any {
        switch self {
        case let .bool(bool): bool
        case let .text(text): text
        case let .list(list): list
        }
    }

    var text: String? {
        if case let .text(text) = self {
            text
        } else {
            nil
        }
    }
}

public extension PluginManifest.Item {
    init(json: Any) {
        let item = json as? [String: Any] ?? [:]
        (value, title, symbol) = (item["value"] as? String, item["title"] as? String, item["symbol"] as? String)
    }
}
