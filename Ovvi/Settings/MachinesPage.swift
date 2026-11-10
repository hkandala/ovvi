import SwiftUI

/// ponytail: no drag to reorder (a grouped form takes no `onMove`); a List section if users ask.
struct MachinesPage: View {
    var body: some View {
        let list = MachineList.shared
        Form {
            Section {
                NavigationLink(value: SettingsDetail.machine(Machine.thisMac.id)) {
                    MachineLabel(machine: .thisMac, detail: Machine.computerName)
                }
                .accessibilityIdentifier("settings.machine.\(Machine.thisMac.id)")
                ForEach(list.list) { machine in
                    NavigationLink(value: SettingsDetail.machine(machine.id)) {
                        MachineLabel(machine: machine, detail: machine.target)
                    }
                    .accessibilityIdentifier("settings.machine.\(machine.id)")
                }
            } header: {
                HStack {
                    Text("Machines")
                    Spacer()
                    NavigationLink("Add Machine…", value: SettingsDetail.machine(MachinePage.new))
                        .controlSize(.small).accessibilityIdentifier("settings.machines.add")
                }
                .settingsRow("machines.list")
            }
        }
    }
}

private struct MachineLabel: View {
    let machine: Machine
    let detail: String
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 10) {
            // The width of an agent's or a plugin's tile: names line up across pages.
            Image(systemName: machine.icon).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(machine.name)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if machine.isRemote {
                let live = MachinePage.isLive(machine)
                Label(live ? "Connected" : "Not connected", systemImage: "circle.fill")
                    .labelStyle(StatusLabel(color: live ? look.finished : .secondary))
            }
        }
    }

    private struct StatusLabel: LabelStyle {
        let color: Color

        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 5) {
                configuration.icon.font(.system(size: 7)).foregroundStyle(color)
                configuration.title.font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct PrivacyPage: View {
    /// The approvals are plain defaults: no view observes them.
    @State private var version = 0

    var body: some View {
        let _ = version // swiftlint:disable:this redundant_discardable_let
        Form {
            ForEach(MachineList.shared.all) { machine in
                let sites = Browser.approvals(machine.id)
                Section {
                    ForEach(sites, id: \.self) { site in
                        LabeledContent(site) {
                            // A card may have approved a site since this drew.
                            Button("Remove") { set(Browser.approvals(machine.id).filter { $0 != site }, machine) }
                                .accessibilityIdentifier("settings.privacy.\(machine.id).\(site).remove")
                        }
                    }
                    if sites.isEmpty {
                        Text("No approved websites.").foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.privacy.\(machine.id).empty")
                    }
                    AddSite(machine: machine) { site in
                        Browser.approve(site, machine.id)
                        version += 1
                    }
                } header: {
                    HStack {
                        Text("Approved websites on \(machine.name)")
                        Spacer()
                        if !sites.isEmpty {
                            Button("Clear All") { set([], machine) }.controlSize(.small)
                        }
                    }
                }
            }
            Section {} footer: {
                Text("A page from a machine loads by itself only from these sites, its localhost and a short safe "
                    + "list. Ovvi adds a site when you open it.").settingsFooter().settingsRow("privacy.websites")
            }
        }
    }

    private func set(_ sites: [String], _ machine: Machine) {
        Browser.setApprovals(sites, machine.id)
        version += 1
    }
}

private struct AddSite: View {
    let machine: Machine
    let add: (String) -> Void
    @State private var text = ""

    private var origin: String? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        let host = URL(string: "http://\(typed)")?.host?.lowercased() ?? ""
        let loopback = Browser.isLoopback(host)
        let full = typed.contains("://") ? typed : (loopback ? "http://" : "https://") + typed
        return Browser.url(full, local: false).map(Browser.origin)
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Website", text: $text, prompt: Text("Website address")).labelsHidden()
                .textFieldStyle(.roundedBorder).onSubmit(save)
                .accessibilityIdentifier("settings.privacy.\(machine.id).field")
            Button("Add", action: save).disabled(origin == nil)
                .accessibilityIdentifier("settings.privacy.\(machine.id).add")
        }
    }

    private func save() {
        guard let origin else { return }
        add(origin)
        text = ""
    }
}
