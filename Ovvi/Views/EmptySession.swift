import HerdrKit
import SwiftUI

/// A live session with no space (ui/states): Ovvi's icon over what a space is, New Space and Open Folder…, then the
/// machine's Git projects most recently changed, each a click from a space of its own.
struct EmptySession: View {
    let page: Page
    /// The projects' folders on the session's machine, newest change first; nil while they are read.
    @State private var projects: [String]?

    var body: some View {
        let store = page.store
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("This session has no spaces").font(.system(size: 15, weight: .semibold)).padding(.top, 12)
                .accessibilityIdentifier("detail.empty")
            Text("A space is a project folder, with its own tabs and terminals.").font(.system(size: 13))
                .foregroundStyle(.secondary).padding(.top, 4)
            HStack(spacing: 8) {
                Button { Task { await page.newWorkspace() } } label: {
                    Text("New Space")
                    Text(KeyboardShortcut.newWorkspace.glyphs).foregroundStyle(.secondary)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("detail.new-workspace")
                Button("Open Folder…") { Task { await openFolder() } }.buttonStyle(.glass)
                    .accessibilityIdentifier("detail.open-folder")
            }
            .controlSize(.large)
            .padding(.top, 16)
            if let projects, !projects.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Git projects").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.bottom, 2)
                    ForEach(projects, id: \.self) { folder in
                        Button { Task { await page.newWorkspace(cwd: folder) } } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder").foregroundStyle(.secondary).frame(width: 18)
                                Text((folder as NSString).lastPathComponent).lineLimit(1)
                                Text(PathField.short(folder, remote: store.machine.isRemote))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .contentShape(.rect)
                        }
                        .buttonStyle(ChromeStyle(radius: 6))
                        .accessibilityIdentifier("detail.project.\(folder)")
                    }
                }
                .frame(width: 360)
                .padding(.top, 28)
            }
        }
        .padding(24)
        .task(id: store.machine.target) { projects = await Self.projects(on: store.machine) }
    }

    /// One shell run on the machine (This Mac or a remote one, over its connection): the Git repositories one level
    /// down the usual code folders of the home folder, by their `.git`'s change time.
    private static func projects(on machine: Machine) async -> [String] {
        let folders = ["code", "Projects", "src", "Developer", "dev", "repos", "git", "work"]
        let script = #"cd "$HOME" && ls -1td "# + folders.map { "\($0)/*/.git" }.joined(separator: " ")
            + #" 2>/dev/null | head -n 6 | sed "s|^|$HOME/|; s|/\.git$||""#
        let text = await (try? machine.exec().output(["sh", "-c", script], timeout: .seconds(5))) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    private func openFolder() async {
        guard let window = NSApp.keyWindow,
              let folder = await page.store.chooseFolder(from: "~", in: window)
        else { return }
        await page.newWorkspace(cwd: folder)
    }
}
