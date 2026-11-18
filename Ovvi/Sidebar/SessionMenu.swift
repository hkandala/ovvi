import SwiftUI

/// The session's menu: on the session header's title and on the sidebar's empty area under the rows.
struct SessionMenu: View {
    let page: Page
    let pages: WindowPages
    let openSession: () -> Void
    @AppStorage(Page.foldsAndShelves, store: .sidebar) private var opened = ""
    private var settings = AppSettings()

    var body: some View {
        Button("New Space") { Task { await page.newWorkspace() } }
            .disabled(page.store.state != .live)
        Button("Open Session…", action: openSession)
        if settings.showArchived {
            let shown = opened.hasLine(pages.agentsKey) && opened.hasLine(pages.archivedKey)
            Button(shown ? "Hide Archived Sessions" : "Show Archived Sessions") {
                withAnimation(.fade) {
                    opened = opened.withLine(pages.agentsKey, !shown).withLine(pages.archivedKey, !shown)
                }
            }
        }
        Button(page.store.onlyPinned ? "Show All Spaces" : "Show Only Pinned Spaces") {
            afterMenu { page.store.onlyPinned.toggle() }
        }
        .disabled(page.store.pins.isEmpty)
        Divider()
        Button("Detach Session") { pages.close(page) }.disabled(!pages.canDetach)
    }
}
