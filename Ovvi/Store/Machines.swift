import Foundation
import HerdrKit
import IOKit.ps
import Observation
import SystemConfiguration

struct Machine: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var target: String
    var icon: String

    var isRemote: Bool {
        !target.isEmpty
    }
}

/// `hw.model` says no MacBook on M2 and later laptops: a laptop is a Mac with an internal battery.
let thisMacIcon: String = {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return "desktopcomputer" }
    let battery = sources.contains { source in
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
    }
    return battery ? "laptopcomputer" : "desktopcomputer"
}()

extension Machine {
    static let thisMac = Machine(id: "local", name: "This Mac", target: "", icon: thisMacIcon)
    static var new: Machine {
        Machine(id: UUID().uuidString, name: "", target: "", icon: "server.rack")
    }

    /// Read once: a rename shows after a relaunch.
    static let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? thisMac.name

    /// The sessions of a remote machine share its ControlMaster.
    @MainActor func exec() async -> any Exec {
        let local = await localExec.value
        guard isRemote else { return local }
        if let exec = Self.execs[target] {
            return exec
        }
        let exec = SSHExec(target: target, local: local)
        Self.execs[target] = exec
        return exec
    }

    /// By target, as the sockets are: two machines of one target share a master.
    @MainActor private static var execs: [String: SSHExec] = [:]

    @MainActor static func disconnectAll() {
        execs.values.forEach { $0.disconnect() }
    }
}

/// A run with `-session` (the tests, a run against a throwaway session) never sees the user's machines.
@MainActor @Observable
final class MachineList {
    static let shared = MachineList()

    var list: [Machine] {
        didSet {
            if !Self.isolated, let data = try? JSONEncoder().encode(list) {
                UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: "machines")
            }
        }
    }

    /// The raw arguments: the argument domain drops a JSON value it cannot read as a property list (`-machines []`).
    static let isolated = ProcessInfo.processInfo.arguments
        .contains { ["-session", "-defaultSession", "-machines"].contains($0) }
    private static let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    static let session = arguments["session"] as? String
    static let defaultSession = arguments["defaultSession"] as? String
    static let machine = arguments["machine"] as? String

    private init() {
        // The argument as given: the argument domain reads a JSON array as something else.
        let arguments = ProcessInfo.processInfo.arguments
        let json = Self.isolated
            ? arguments.firstIndex(of: "-machines").flatMap { arguments.dropFirst($0 + 1).first }
            : UserDefaults.standard.string(forKey: "machines")
        list = json.flatMap { try? JSONDecoder().decode([Machine].self, from: Data($0.utf8)) } ?? []
    }

    /// Open sessions take the name and icon only: they stay connected to the target they opened on.
    func save(_ machine: Machine) {
        guard let index = list.firstIndex(where: { $0.id == machine.id }) else { return }
        list[index] = machine
        for window in WindowPages.windows where window.machine.id == machine.id {
            window.machine = machine
        }
        for store in HostStore.all where store.machine.id == machine.id {
            store.machine.name = machine.name
            store.machine.icon = machine.icon
        }
    }

    func keep(_ draft: Machine, target: String) -> Machine {
        var machine = draft
        let name = machine.name.trimmingCharacters(in: .whitespaces)
        machine.name = name.isEmpty ? target : name
        machine.target = target
        if list.contains(where: { $0.id == machine.id }) {
            save(machine)
        } else {
            list.append(machine)
            WindowPages.added(machine)
        }
        return machine
    }

    func remove(_ machine: Machine) {
        list.removeAll { $0.id == machine.id }
        Browser.forget(machine)
        KnownSessions.forget(machine)
    }

    var all: [Machine] {
        [.thisMac] + list
    }

    func machine(_ id: String) -> Machine? {
        id == Machine.thisMac.id ? .thisMac : list.first { $0.id == id }
    }
}

extension Session {
    /// The session herdr makes when a command names none.
    static let defaultName = "default"
}
