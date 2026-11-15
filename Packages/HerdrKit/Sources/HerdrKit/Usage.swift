import Foundation

/// Anonymous usage data (docs/content/docs/telemetry.mdx): one `app_day` event per day of use, with yes or no for each
/// feature used that day. The event holds only fixed values, numbers and booleans: nothing of the user's can reach it.
/// A day goes once it has ended, at the next launch or hourly send, so its flags are complete and it counts once.
@MainActor
public final class Usage {
    public enum Feature: String, CaseIterable, Sendable {
        case remoteMachines = "remote_machines", browserCard = "browser_card", fileExplorer = "file_explorer", git
        case pluginCard = "plugin_card", chatView = "chat_view", palette, overview, floatingWindow = "floating_window"
        case cli, fileDrop = "file_drop"
        case agentClaude = "agent_claude", agentCodex = "agent_codex", agentOpenCode = "agent_opencode"
        case agentPi = "agent_pi", agentOther = "agent_other"

        public init(plugin id: String) {
            self = ["explorer": .fileExplorer, "git": .git][id] ?? .pluginCard
        }

        /// herdr's agent name.
        public init(agent name: String) {
            self = Self(rawValue: "agent_" + name) ?? .agentOther
        }
    }

    /// Ephemeral, with no cookie store: nothing kept between requests.
    private static let session = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()

    private let key: String
    private let defaults: UserDefaults
    private let endpoint: URL?
    private let log: URL
    /// Today's flags as stored: a feature used again costs no write.
    private var seen: (day: Int, features: Set<Feature>)?

    public init(
        key: String,
        log: URL,
        defaults: UserDefaults = .standard,
        endpoint: URL? = URL(string: "https://e.ovvi.dev/batch/"),
    ) {
        self.key = key
        self.log = log
        self.defaults = defaults
        self.endpoint = endpoint
    }

    /// `DO_NOT_TRACK=1` or `true` (consoledonottrack.com), or `OVVI_TELEMETRY=0`.
    public nonisolated static func optedOut(_ environment: [String: String]) -> Bool {
        ["1", "true"].contains(environment["DO_NOT_TRACK"]?.lowercased()) || environment["OVVI_TELEMETRY"] == "0"
    }

    /// Settings ▸ General ▸ Share anonymous usage data (`usageData` in AppSettings).
    private var sharing: Bool {
        defaults.object(forKey: "usageData") as? Bool ?? true
    }

    /// Pending days: days since 1970 by the Mac's calendar date, each with its features.
    private var days: [Int: Set<Feature>] {
        get {
            let stored = defaults.dictionary(forKey: "usageDays") as? [String: [String]] ?? [:]
            return Dictionary(uniqueKeysWithValues: stored.compactMap { day, features in
                Int(day).map { ($0, Set(features.compactMap(Feature.init(rawValue:)))) }
            })
        }
        set {
            defaults.set(Dictionary(uniqueKeysWithValues: newValue.map { (String($0), $1.map(\.rawValue).sorted()) }),
                         forKey: "usageDays")
        }
    }

    /// The Mac's date as days since 1970, by its offset from UTC at that moment: any calendar, DST too.
    static func day(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: date))) / 86400)
    }

    /// Today is a day of use; nil marks only that.
    public func used(_ feature: Feature? = nil, at now: Date = .now) {
        let day = Self.day(now)
        if let seen, seen.day == day, feature.map(seen.features.contains) ?? true {
            return
        }
        guard sharing else { return }
        var features = days[day] ?? []
        if let feature {
            features.insert(feature)
        }
        days[day] = features
        seen = (day, features)
    }

    /// Turning the switch off, or a variable that opts out.
    public func forget() {
        defaults.removeObject(forKey: "usageID")
        defaults.removeObject(forKey: "usageDays")
        seen = nil
    }

    /// Every day that has ended, in one request. A failed send keeps them for the next; a day older than 7 goes.
    public func send(at now: Date = .now) async {
        guard sharing else { return forget() }
        let today = Self.day(now)
        days = days.filter { $0.key >= today - 7 }
        let ended = days.filter { $0.key < today }
        guard !ended.isEmpty, let endpoint else { return }
        let id = defaults.string(forKey: "usageID") ?? UUID().uuidString
        defaults.set(id, forKey: "usageID")
        let events = ended.sorted { $0.key < $1.key }.map { Self.event(day: $0.key, features: $0.value, id: id) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // URLSession's own would tell the user's languages.
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["api_key": key, "batch": events])
        guard let (_, response) = try? await Self.session.data(for: request),
              (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) == true else { return }
        days = days.filter { ended[$0.key] == nil }
        write(events)
    }

    static func event(day: Int, features: Set<Feature>, id: String) -> [String: Any] {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        var properties: [String: Any] = [
            "$process_person_profile": false, "$geoip_disable": true,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "build": Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0,
            "os": "\(system.majorVersion).\(system.minorVersion)", "arch": arch,
        ]
        for feature in Feature.allCases {
            properties[feature.rawValue] = features.contains(feature)
        }
        // Noon UTC of the day's date: the date alone, no time of day or time zone.
        let timestamp = Date(timeIntervalSince1970: Double(day) * 86400 + 43200).ISO8601Format()
        return ["event": "app_day", "distinct_id": id, "timestamp": timestamp, "properties": properties]
    }

    #if arch(arm64)
        static let arch = "arm64"
    #else
        static let arch = "x86_64"
    #endif

    /// The last 7 events sent, as JSON lines.
    private func write(_ events: [[String: Any]]) {
        let old = (try? String(contentsOf: log, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        let new = events.compactMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }
            .map { String(decoding: $0, as: UTF8.self) }
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (old + new).suffix(7).map { $0 + "\n" }.joined().write(to: log, atomically: true, encoding: .utf8)
    }
}
