import AppKit
import HerdrKit
import SwiftUI

/// Anonymous usage data ([Usage data](/docs/telemetry)). Only the released app has the key (`make zip`); Debug builds,
/// Ovvi Dev, the measures' `make app` and runs with `-session` (the UI tests) record and send nothing.
enum Telemetry {
    static let log = URL.homeDirectory.appending(path: "Library/Logs/\(Registry.logs)/usage.log")
    private static let key = Bundle.main.object(forInfoDictionaryKey: "OvviPostHogKey") as? String ?? ""
    private(set) static var usage = key.isEmpty || MachineList.isolated ? nil : Usage(key: key, log: log)

    static func used(_ feature: Usage.Feature) {
        usage?.used(feature)
    }

    /// Each snapshot: a remote machine's session and the agents in it.
    static func saw(_ snapshot: Snapshot, remote: Bool) {
        guard let usage else { return }
        if remote {
            usage.used(.remoteMachines)
        }
        for agent in snapshot.agents.compactMap(\.agent) {
            usage.used(Usage.Feature(agent: agent))
        }
    }

    /// Once the login shell's variables are in, then every hour: a day that ended while the app ran goes too.
    static func start() {
        guard usage != nil else { return }
        Task {
            if await Usage.optedOut(localExec.value.environment) {
                usage?.forget()
                usage = nil
            }
            while let usage {
                usage.used()
                await usage.send()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    /// Help ▸ Usage Data Log, once a send wrote it.
    static var commands: [Command] {
        guard usage != nil else { return [] }
        return [Command(section: .help, title: "Usage Data Log", symbol: "doc.text",
                        keywords: "telemetry analytics privacy anonymous",
                        enabled: FileManager.default.fileExists(atPath: log.path)) { NSWorkspace.shared.open(log) }]
    }
}

/// Settings ▸ General.
struct UsageSwitch: View {
    private var settings = AppSettings()

    var body: some View {
        Toggle(isOn: settings.$usageData) {
            Text("Share anonymous usage data")
            Text("Counts of features used, no names or paths. [What it sends](https://ovvi.dev/docs/telemetry)")
        }
        .identifiedSettingsRow("general.usage")
        .onChange(of: settings.usageData) {
            if !settings.usageData {
                Telemetry.usage?.forget()
            }
        }
    }
}
