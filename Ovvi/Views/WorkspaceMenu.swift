import HerdrKit
import SwiftUI

/// With the sidebar collapsed it is there, hidden, through every drag of the page in view, until a hold over the button
/// opens it: macOS 27 finds no drop target added after the drag entered the window.
struct WorkspaceMenu: View {
    let pages: WindowPages
    let page: Page
    @Binding var open: Bool
    let openSession: () -> Void

    var body: some View {
        let rows = pages.list.flatMap { page in page.store.workspaces.map { (page, $0) } }
        FilterList(prompt: "Filter or create…", name: "workspaces", items: items,
                   start: rows.firstIndex { $0.0 === page && $0.1.id == page.selectedWorkspaceID } ?? 0,
                   maxHeight: 340, pinned: 2, autofocus: page.dragging == nil) { open = false }
            .padding(8)
            .frame(width: 300)
            .floatingGlass(in: .rect(cornerRadius: 12))
            .clearsDrop(page) { open = false }
    }

    private func items(_ filter: String) -> [FilterList.Item] {
        let workspaces = pages.list.flatMap { page in
            page.store.workspaces.filter { $0.label.matches(filter) }.map { workspace in
                FilterList.Item(id: "\(page.id).\(workspace.id)",
                                state: workspace.state,
                                title: workspace.label,
                                detail: workspace.git?.branch ?? "", section: page.id,
                                drop: page === self.page ? MenuRowDrop.Target(
                                    page: page, destination: .newTab(workspaceID: workspace.id), shown: open,
                                ) : nil, act: {
                                    pages.show(page)
                                    page.select(workspace)
                                })
            }
        }
        let typed = filter.trimmingCharacters(in: .whitespaces)
        let create = typed.isEmpty || !workspaces.isEmpty ? [] : [
            FilterList.Item(id: "create", symbol: "plus", title: "New Space “\(typed)”") {
                Task { await page.newWorkspace(label: typed) }
            },
        ]
        return create + workspaces + [
            FilterList.Item(id: "new", symbol: "plus", title: "New Space", section: "",
                            drop: MenuRowDrop.Target(page: page, destination: .newWorkspace(), shown: open),
                            act: { Task { await page.newWorkspace() } }),
            FilterList.Item(id: "open-session", symbol: "plus.square.on.square", title: "Open Session…",
                            detail: KeyboardShortcut.openSession.glyphs, section: "", act: openSession),
        ]
    }
}
