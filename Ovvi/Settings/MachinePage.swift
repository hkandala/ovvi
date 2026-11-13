import HerdrKit
import SwiftUI

struct MachinePage: View {
    static let new = "new"
    let id: String
    @State private var draft: Machine
    @State private var confirm: Confirm?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.look) private var look

    private enum Confirm {
        case clear, remove
    }

    static func isLive(_ machine: Machine) -> Bool {
        HostStore.all.contains { $0.machine.id == machine.id && $0.state == .live }
    }

    private static func state(_ saved: Machine?) -> [String] {
        guard let saved else { return ["Not added yet"] }
        return [saved.isRemote ? isLive(saved) ? "Connected" : "Not connected" : Machine.computerName]
    }

    private var question: String {
        let name = MachineList.shared.machine(id)?.name ?? ""
        return confirm == .clear ? "Clear the website data of \(name)?" : "Remove \(name)?"
    }

    private var target: String {
        draft.target.trimmingCharacters(in: .whitespaces)
    }

    private var confirming: Binding<Bool> {
        Binding { confirm != nil } set: {
            if !$0 {
                confirm = nil
            }
        }
    }

    init(id: String) {
        self.id = id
        _draft = State(initialValue: MachineList.shared.machine(id)
            ?? .new)
    }

    var body: some View {
        let saved = MachineList.shared.machine(id)
        let name = draft.name.isEmpty ? target : draft.name
        Form {
            Section {
                SettingsHeader(title: saved?.name ?? (name.isEmpty ? "New Machine" : name), lines: Self.state(saved)) {
                    Image(systemName: saved?.icon ?? draft.icon).font(.system(size: 20)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 36).background(.quaternary, in: .rect(cornerRadius: 10))
                }
            }
            if draft.isRemote || saved == nil {
                connection(saved)
            }
            if let saved {
                Section("Browser") {
                    LabeledContent {
                        Button("Clear…") { confirm = .clear }.accessibilityIdentifier("settings.machine.clear")
                    } label: {
                        Text("Website data")
                        Text("Logins and approved websites of browser cards on \(saved.name).")
                    }
                }
                if saved.isRemote {
                    Section {
                        LabeledContent {
                            Button("Remove…", role: .destructive) { confirm = .remove }
                                .accessibilityIdentifier("settings.machine.remove")
                        } label: {
                            Text("Remove \(saved.name)")
                            Text("Ovvi forgets it. Its terminals keep running on it.")
                        }
                    }
                }
            }
        }
        // A pushed page takes no style from the stack it is pushed on.
        .formStyle(.grouped)
        .navigationTitle(saved?.name ?? "Add Machine")
        // The buttons and the message keep their words while the alert closes: `confirm` is nil by then.
        .alert(question, isPresented: confirming, presenting: confirm) { which in
            Button(which == .clear ? "Clear" : "Remove", role: .destructive) {
                if let saved, which == .clear {
                    Browser.clear(saved)
                } else if let saved {
                    MachineList.shared.remove(saved)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { which in
            Text(which == .clear ? "Browser cards log out of every site, and pages wait for Open again."
                : "Ovvi forgets it. Its terminals keep running on it.")
        }
    }

    private func connection(_ saved: Machine?) -> some View {
        Section {
            // A set width: a form's text field asks for all the room and narrows the sidebar.
            LabeledContent("Name") {
                TextField("Name", text: $draft.name, prompt: Text(target.isEmpty ? "Optional" : target))
                    .labelsHidden().multilineTextAlignment(.trailing).truncationMode(.middle).frame(width: 220)
                    .accessibilityIdentifier("settings.machine.name")
            }
            LabeledContent {
                TextField("SSH target", text: $draft.target, prompt: Text("Required")).labelsHidden()
                    .multilineTextAlignment(.trailing).truncationMode(.middle).frame(width: 220)
                    .accessibilityIdentifier("settings.machine.target")
            } label: {
                Text("SSH target")
                Text("A host from ~/.ssh/config works too.")
            }
            // The dialog's glass button is taller than the form's: its label on the button's middle.
            LabeledContent("Icon") {
                IconPicker(icon: $draft.icon).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
        } header: {
            Text("Connection")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                if !target.isEmpty, !SSHExec.isValidTarget(target) {
                    Text("An SSH target has no spaces and does not start with -.")
                        .font(.system(size: 11)).foregroundStyle(look.error)
                        .accessibilityIdentifier("settings.machine.problem")
                }
                Spacer()
                if saved == nil {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                Button(saved == nil ? "Add" : "Save", action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!SSHExec.isValidTarget(target) || saved == draft)
                    .accessibilityIdentifier("settings.machine.save")
            }
        }
    }

    /// Reads the page as it is now, never the body's values: Return runs the action SwiftUI kept when the button
    /// turned on, at the first letter typed.
    private func save() {
        let added = MachineList.shared.machine(id) == nil
        guard SSHExec.isValidTarget(target) else { return }
        draft = MachineList.shared.keep(draft, target: target)
        // The new machine's window comes forward, where ssh asks what it asks.
        if added {
            dismiss()
            dismissWindow(id: WindowPages.settingsScene)
        }
    }
}
