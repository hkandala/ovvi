import SwiftUI

/// A live session with no space (ui/states): Ovvi's icon over what a space is, then New Space and Open Folder….
struct EmptySession: View {
    let page: Page

    var body: some View {
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
        }
        .padding(24)
    }

    private func openFolder() async {
        guard let window = NSApp.keyWindow,
              let folder = await page.store.chooseFolder(from: "~", in: window)
        else { return }
        await page.newWorkspace(cwd: folder)
    }
}
