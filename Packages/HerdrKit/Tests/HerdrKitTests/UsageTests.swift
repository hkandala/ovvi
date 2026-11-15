import Foundation
@testable import HerdrKit
import Network
import Synchronization
import Testing

private let day = TimeInterval(86400)

/// A usage store of its own, a log in a temporary folder, and a local server that answers `status` and keeps each
/// request's JSON.
private final class Requests: Sendable {
    let bodies = Mutex<[Data]>([])
}

@MainActor
private final class Rig {
    let usage: Usage, defaults: UserDefaults, log: URL, server: NWListener
    let requests = Requests()

    init(status: Int = 200) async throws {
        let name = "usage-test-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: name))
        log = FileManager.default.temporaryDirectory.appending(path: "\(name)/usage.log")
        let server = try NWListener(using: .tcp, on: .any)
        server.newConnectionHandler = { [requests] connection in
            connection.start(queue: .global())
            Task {
                var request = Data()
                while let some = await connection.readSome() {
                    request += some
                    guard let end = request.range(of: Data("\r\n\r\n".utf8)) else { continue }
                    let head = String(decoding: request[..<end.lowerBound], as: UTF8.self).lowercased()
                    let length = head.firstMatch(of: /content-length: (\d+)/).flatMap { Int($0.1) } ?? 0
                    guard request.count - end.upperBound >= length else { continue }
                    requests.bodies.withLock { $0.append(Data(request[end.upperBound...])) }
                    let reply = "HTTP/1.1 \(status) X\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    connection.send(
                        content: Data(reply.utf8),
                        completion: .contentProcessed { _ in connection.cancel() },
                    )
                    return
                }
            }
        }
        let ready = AsyncStream<Void> { continuation in
            server.stateUpdateHandler = {
                if $0 == .ready {
                    continuation.finish()
                }
            }
        }
        server.start(queue: .global())
        for await _ in ready {}
        self.server = server
        let port = try #require(server.port?.rawValue)
        usage = Usage(key: "phc_test", log: log, defaults: defaults,
                      endpoint: URL(string: "http://127.0.0.1:\(port)/batch/"))
    }

    var bodies: [[String: Any]] {
        requests.bodies.withLock { $0 }.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    var events: [[String: Any]] {
        bodies.flatMap { $0["batch"] as? [[String: Any]] ?? [] }
    }

    var pending: [String: [String]] {
        defaults.dictionary(forKey: "usageDays") as? [String: [String]] ?? [:]
    }

    func close() {
        server.cancel()
        try? FileManager.default.removeItem(at: log.deletingLastPathComponent())
    }
}

@MainActor @Test func `a day goes once, after it ended, with its features`() async throws {
    let rig = try await Rig()
    defer { rig.close() }
    let monday = Date(timeIntervalSince1970: 1_800_000_000)
    rig.usage.used(.palette, at: monday)
    rig.usage.used(.git, at: monday)
    rig.usage.used(.palette, at: monday)
    await rig.usage.send(at: monday)
    #expect(rig.bodies.isEmpty)

    rig.usage.used(.overview, at: monday + day)
    await rig.usage.send(at: monday + day)
    let body = try #require(rig.bodies.first)
    #expect(body["api_key"] as? String == "phc_test")
    let event = try #require(rig.events.first)
    let properties = try #require(event["properties"] as? [String: Any])
    #expect(rig.events.count == 1)
    #expect(event["event"] as? String == "app_day")
    #expect(event["distinct_id"] as? String == rig.defaults.string(forKey: "usageID"))
    let date = Calendar.current.dateComponents([.year, .month, .day], from: monday)
    let noon = try String(format: "%04d-%02d-%02dT12:00:00Z", #require(date.year), #require(date.month),
                          #require(date.day))
    #expect(event["timestamp"] as? String == noon)
    let used = Set(Usage.Feature.allCases.filter { properties[$0.rawValue] as? Bool == true })
    #expect(used == [.palette, .git])
    // Today waits for tomorrow; Monday went.
    #expect(Array(rig.pending.keys) == [String(Usage.day(monday + day))])
    await rig.usage.send(at: monday + day)
    #expect(rig.events.count == 1)
    let log = try String(contentsOf: rig.log, encoding: .utf8)
    #expect(log.split(separator: "\n").count == 1 && log.contains(#""event":"app_day""#))
}

@MainActor @Test func `a failed send keeps the day for 7 days`() async throws {
    let rig = try await Rig(status: 503)
    defer { rig.close() }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    rig.usage.used(.cli, at: start)
    await rig.usage.send(at: start + day)
    await rig.usage.send(at: start + 7 * day)
    #expect(rig.events.count == 2)
    #expect(rig.pending.count == 1)
    #expect(!FileManager.default.fileExists(atPath: rig.log.path))
    await rig.usage.send(at: start + 8 * day)
    #expect(rig.events.count == 2)
    #expect(rig.pending.isEmpty)
}

@MainActor @Test func `the switch off deletes the id and the days and records nothing`() async throws {
    let rig = try await Rig()
    defer { rig.close() }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    rig.usage.used(.browserCard, at: start)
    await rig.usage.send(at: start + day)
    rig.usage.used(.browserCard, at: start + day)
    #expect(rig.defaults.string(forKey: "usageID") != nil && !rig.pending.isEmpty)
    rig.defaults.set(false, forKey: "usageData")
    rig.usage.forget()
    #expect(rig.defaults.string(forKey: "usageID") == nil && rig.pending.isEmpty)
    rig.usage.used(.browserCard, at: start + day)
    rig.usage.used(.git, at: start + day)
    await rig.usage.send(at: start + 2 * day)
    #expect(rig.pending.isEmpty && rig.events.count == 1)
    // On again: a new id.
    let old = rig.events[0]["distinct_id"] as? String
    rig.defaults.set(true, forKey: "usageData")
    rig.usage.used(.git, at: start + 2 * day)
    await rig.usage.send(at: start + 3 * day)
    let new = try #require(rig.events.last?["distinct_id"] as? String)
    #expect(rig.events.count == 2 && new != old)
}

@Test func `DO_NOT_TRACK and OVVI_TELEMETRY opt out`() {
    for out in [["DO_NOT_TRACK": "1"], ["DO_NOT_TRACK": "true"], ["DO_NOT_TRACK": "TRUE"], ["OVVI_TELEMETRY": "0"]] {
        #expect(Usage.optedOut(out))
    }
    for staying in [[:], ["DO_NOT_TRACK": "0"], ["DO_NOT_TRACK": "false"], ["OVVI_TELEMETRY": "1"]] {
        #expect(!Usage.optedOut(staying))
    }
}

@Test func `agents and plugins map to fixed features`() {
    #expect(Usage.Feature(agent: "claude") == .agentClaude)
    #expect(Usage.Feature(agent: "opencode") == .agentOpenCode)
    #expect(Usage.Feature(agent: "aider") == .agentOther)
    #expect(Usage.Feature(plugin: "explorer") == .fileExplorer)
    #expect(Usage.Feature(plugin: "git") == .git)
    #expect(Usage.Feature(plugin: "my-plugin") == .pluginCard)
}

/// Every key the event sends is a row of the docs page's field table, and every row a key; only `version`, `os` and
/// `arch` are strings, of fixed shapes.
@MainActor @Test func `the event's keys are the docs table's`() throws {
    let event = Usage.event(day: 20000, features: [.chatView], id: UUID().uuidString)
    let properties = try #require(event["properties"] as? [String: Any])
    let docs = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../docs/content/docs/telemetry.mdx"), encoding: .utf8)
    let rows = Set(docs.matches(of: /\n\| `([^`]+)` \|/).map { String($0.1) })
    #expect(rows == Set(properties.keys).union(event.keys).subtracting(["properties"]))
    for (key, value) in properties {
        switch key {
        case "version": #expect((value as? String)?.wholeMatch(of: /(\d+(\.\d+)*(-[a-z0-9.]+)?)?/) != nil)
        case "os": #expect((value as? String)?.wholeMatch(of: /\d+\.\d+/) != nil)
        case "arch": #expect(["arm64", "x86_64"].contains(value as? String))
        case "build": #expect(value is Int)
        default: #expect(value is Bool, "\(key)")
        }
    }
    #expect(properties["chat_view"] as? Bool == true && properties["$ip"] == nil)
}
