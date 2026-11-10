import AppKit
import HerdrKit
import SwiftUI

struct NewPaneFolder: View {
    let chooser: Chooser
    let page: Page
    let cardID: String
    static let height: CGFloat = 44
    @State private var draft = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    @Environment(\.look) private var look

    var body: some View {
        let store = page.store, remote = store.machine.isRemote
        // Not on a stand-in: herdr's pane, as it shows, gives its terminal the keyboard and would close the field.
        let editing = chooser.editing && store.pane(cardID) != nil
        if let folder = chooser.folder ?? store.pane(cardID)?.cwd ?? chooser.cwd {
            VStack(spacing: 4) {
                // The icon is one view in both looks: a click on it as the field lets go still lands.
                HStack(spacing: 6) {
                    if !remote {
                        choose(folder).foregroundStyle(editing ? AnyShapeStyle(.secondary) : dim)
                    }
                    if editing {
                        field(folder)
                    } else {
                        line(folder, remote: remote, machine: store.machine.name)
                    }
                }
                .frame(maxWidth: editing ? .infinity : nil)
                .fieldCapsule(fill: editing)
                .overlay { Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5).opacity(editing ? 1 : 0) }
                .font(.system(size: 12))
                .frame(height: 26)
                Text(error ?? "").font(.system(size: 11)).foregroundStyle(look.error).lineLimit(1).frame(height: 14)
                    .accessibilityIdentifier("pane.\(cardID).chooser.folder.error")
                    .accessibilityHidden(error == nil)
            }
            .onChange(of: chooser.editing, initial: true) {
                if chooser.editing, page.store.pane(cardID) == nil {
                    chooser.editing = false
                }
                draft = folder
                error = nil
            }
            .onChange(of: draft) { error = nil }
            .onChange(of: focused) {
                if focused {
                    DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSText)?.selectAll(nil) }
                } else {
                    chooser.editing = false
                }
            }
            .onAppear { chooser.editing = false }
            .onDisappear { chooser.editing = false }
        }
    }

    private var dim: AnyShapeStyle {
        look.contrast ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
    }

    private func line(_ folder: String, remote: Bool, machine: String) -> some View {
        HStack(spacing: 4) {
            Text("Opens in").foregroundStyle(dim).accessibilityHidden(true)
            Button {
                if let pane = page.store.pane(cardID) {
                    page.go(to: pane)
                }
                chooser.editing = true
            } label: {
                Text(MachinePath.short(folder, remote: remote)).fontWeight(.medium).lineLimit(1).truncationMode(.head)
            }
            .buttonStyle(.plain)
            .foregroundStyle(dim)
            .accessibilityLabel("Opens in")
            .accessibilityValue(folder)
            .accessibilityIdentifier("pane.\(cardID).chooser.folder")
            if remote {
                Text("on \(machine)").foregroundStyle(dim).lineLimit(1)
            }
        }
    }

    private func field(_ folder: String) -> some View {
        TextField("Folder", text: $draft)
            .focused($focused)
            .blursWhenHidden($focused)
            .accessibilityIdentifier("pane.\(cardID).chooser.folder.field")
            .onSubmit { submit(from: folder) }
            .onExitCommand(perform: stop)
            .focusEffectDisabled()
            .focusSoon($focused)
    }

    private func choose(_ folder: String) -> some View {
        Button {
            guard let window = NSApp.keyWindow else { return }
            Task {
                if let path = await page.store.chooseFolder(from: folder, in: window), path != folder {
                    chooser.folder = path
                }
                if chooser.editing {
                    stop()
                }
            }
        } label: {
            Image(systemName: "folder")
        }
        .buttonStyle(.plain)
        .help("Choose Folder…")
        .accessibilityLabel("Choose Folder…")
        .accessibilityIdentifier("pane.\(cardID).chooser.folder.choose")
    }

    private func submit(from folder: String) {
        let typed = draft.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return stop() }
        Task {
            let path = await page.store.folder(typed, from: folder)
            guard chooser.editing, draft.trimmingCharacters(in: .whitespaces) == typed else { return }
            if let path {
                if path != folder {
                    chooser.folder = path
                }
                stop()
            } else {
                error = "No folder \(typed)"
            }
        }
    }

    private func stop() {
        chooser.editing = false
        if let pane = page.store.pane(cardID) {
            page.go(to: pane)
        }
    }
}
