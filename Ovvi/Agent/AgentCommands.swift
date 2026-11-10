import AppKit
import HerdrKit

struct AgentCommand {
    let name: String
    let usage: String
    let summary: String
    var help = ""
    let run: @MainActor (inout AgentCall) async throws -> AgentOutput
}

@MainActor
enum AgentCommands {
    static let all: [AgentCommand] = [
        .help,
        .info,
        .float,
        .unfloat,
        .copy,
        .plugins,
        .open,
        .reveal,
        .card,
        .shown,
        .notify,
        .agent,
        .chat,
        .view,
        .balance,
    ]

    static let script = Bundle.main.url(forResource: "ovvi", withExtension: "sh").flatMap { try? Data(contentsOf: $0) }

    static func run(_ argv: [String], cwd: String, from pane: String, request id: String,
                    store: HostStore) async -> AgentAnswer
    {
        let json = argv.contains("--json")
        var call = AgentCall(store: store, pane: pane, cwd: cwd, id: id, args: argv.filter { $0 != "--json" })
        do {
            let name = call.args.isEmpty ? "help" : call.args.removeFirst()
            guard let command = all.first(where: { $0.name == name }) else {
                throw AgentError.unknownCommand(name)
            }
            let output = try await command.run(&call)
            return AgentAnswer(code: 0, out: json ? output.jsonData : Data(output.text.utf8), err: "")
        } catch {
            return failure(error, json: json)
        }
    }

    static func failure(_ error: Error, json: Bool) -> AgentAnswer {
        let error = error as? AgentError ?? AgentError.failed(error.localizedDescription)
        let out = json ? AgentOutput(["error": ["code": error.code, "message": error.message]]).jsonData : Data()
        return AgentAnswer(code: error.exit, out: out, err: "ovvi: \(error.message)\n")
    }
}

struct AgentAnswer {
    let code: Int32
    let out: Data
    let err: String
}

struct AgentError: Error {
    let code: String
    let message: String

    var exit: Int32 {
        ["usage", "unknown_command", "protocol"].contains(code) ? 2 : 1
    }

    static func usage(_ message: String) -> AgentError {
        AgentError(code: "usage", message: message)
    }

    static func badArgument(_ message: String) -> AgentError {
        AgentError(code: "bad_argument", message: message)
    }

    static func failed(_ message: String) -> AgentError {
        AgentError(code: "failed", message: message)
    }

    static func pluginNotFound(_ message: String) -> AgentError {
        AgentError(code: "plugin_not_found", message: message)
    }

    static func paneNotFound(_ id: String, in session: String) -> AgentError {
        AgentError(code: "pane_not_found", message: "pane \(id) is not in herdr session \(session)")
    }

    static func noWindow(_ session: String) -> AgentError {
        failed("no window shows herdr session \(session)")
    }

    static func unknownCommand(_ name: String) -> AgentError {
        AgentError(code: "unknown_command", message: "no command \(name); `ovvi help` lists them")
    }
}

struct AgentOutput {
    /// Made of dictionaries, arrays, strings, numbers, booleans and `NSNull`.
    let json: Any
    let text: String

    init(_ json: Any, text: String? = nil) {
        self.json = json
        self.text = text ?? (json as? [String: Any] ?? [:]).sorted { $0.key < $1.key }.map { key, value in
            "\(key): \((value as? [Any])?.map { "\($0)" }.joined(separator: ", ") ?? "\(value)")\n"
        }.joined()
    }

    var jsonData: Data {
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]))
        return (data ?? Data("null".utf8)) + Data("\n".utf8)
    }
}

@MainActor
struct AgentCall {
    let store: HostStore
    let pane: String
    let cwd: String
    let id: String
    var args: [String]

    mutating func flag(_ name: String) -> Bool {
        let had = args.contains(name)
        args.removeAll { $0 == name }
        return had
    }

    mutating func value(_ name: String) throws -> String? {
        guard let index = args.firstIndex(of: name) else { return nil }
        guard index + 1 < args.count else { throw AgentError.usage("\(name) needs a value") }
        defer { args.removeSubrange(index ... index + 1) }
        return args[index + 1]
    }

    mutating func argument(_ name: String) throws -> String {
        guard let next = try optionalArgument() else { throw AgentError.usage("missing <\(name)>") }
        return next
    }

    mutating func optionalArgument() throws -> String? {
        guard let next = args.first else { return nil }
        guard !next.hasPrefix("--") else { throw AgentError.usage("unknown option \(next)") }
        return args.removeFirst()
    }

    func done() throws {
        guard let extra = args.first else { return }
        throw AgentError.usage(extra.hasPrefix("--") ? "unknown option \(extra)" : "extra argument \(extra)")
    }

    var asking: PaneTarget {
        PaneTarget(session: store.session, id: pane, machine: store.machine)
    }

    /// The machine is always the asking pane's, so that no argument reaches another one.
    func target(_ argument: String) async throws -> PaneTarget {
        let parts = argument.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let (session, id) = parts.count == 2 ? (parts[0], parts[1]) : (store.session, argument)
        guard !id.isEmpty, !id.hasPrefix("-"), !id.contains("/"), Session.isValidName(session),
              !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw AgentError.badArgument("\(argument) is not a pane") }
        let runs = { store.sessions.contains { $0.name == session && $0.running } }
        if session != store.session, !runs() {
            await store.loadSessions()
        }
        guard session == store.session || runs() else {
            throw AgentError(
                code: "pane_not_found",
                message: "no herdr session \(session) runs on \(store.machine.name)",
            )
        }
        let target = PaneTarget(session: session, id: id, machine: store.machine)
        if let found = target.store, found.state == .live, found.pane(id) == nil {
            throw AgentError.paneNotFound(id, in: session)
        }
        return target
    }
}

@MainActor
struct PaneTarget {
    let session: String
    let id: String
    let machine: Machine

    var store: HostStore? {
        HostStore.all.first { $0.session == session && $0.machine.id == machine.id }
    }
}

extension AgentCommand {
    static let help = AgentCommand(
        name: "help", usage: "help [<command>]", summary: "Lists the commands, or tells more of one",
    ) { call in
        let name = try call.optionalArgument()
        try call.done()
        let all = [.status] + AgentCommands.all
        if let name {
            guard let command = all.first(where: { $0.name == name }) else {
                throw AgentError.unknownCommand(name)
            }
            let text = "usage: ovvi \(command.usage)\n\n\(command.summary).\n"
                + (command.help.isEmpty ? "" : "\n\(command.help)\n")
            return AgentOutput(["name": command.name, "usage": command.usage, "summary": command.summary,
                                "help": command.help], text: text)
        }
        let commands = all.map { ($0.usage, $0.summary) }
        let width = commands.map(\.0.count).max() ?? 0
        let text = """
        usage: ovvi [--pane <pane>] [--timeout <seconds>] <command> [<args>] [--json]

        \(commands.map { "  " + $0.padding(toLength: width + 2, withPad: " ", startingAt: 0) + $1 }
            .joined(separator: "\n"))

        A <pane> is w1:p3 in this session, or <session>/<pane> on this machine. `ovvi help <command>` tells more.

        """
        return AgentOutput(["commands": all.map {
            ["name": $0.name, "usage": $0.usage, "summary": $0.summary]
        }], text: text)
    }

    /// Only for `help`: the script answers `status` itself and never sends it.
    static let status = AgentCommand(
        name: "status", usage: "status [--json | --watch]", summary: "Says if Ovvi shows this pane, from herdr alone",
        help: "Exit 0 when an Ovvi follows the session, 3 when none does. --watch prints a line on each change.",
    ) { _ in throw AgentError.usage("the script answers status") }

    static let info = AgentCommand(
        name: "info", usage: "info", summary: "What this Ovvi offers: version, protocol, commands, agents",
    ) { call in
        try call.done()
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return AgentOutput([
            "app": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "protocol": AgentRequest.version,
            "machine": call.store.machine.name,
            "appearance": dark ? "dark" : "light",
            "commands": AgentCommands.all.map(\.name),
            "agents": Chooser.agents.map(\.command),
        ])
    }
}
