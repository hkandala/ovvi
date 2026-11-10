import HerdrKit
import SwiftUI

struct TitleBar: View {
    static let height: CGFloat = 46

    /// Rex's sidebar toggle is centered 82 pt right of the red light's center.
    static func inset(fullScreen: Bool) -> CGFloat {
        fullScreen ? gap : 91
    }

    let pages: WindowPages
    let page: Page
    let fullScreen: Bool
    @Binding var sidebar: Bool
    let sidebarWidth: CGFloat
    @Binding var palette: Bool
    @Binding var workspaceMenu: Bool
    @Binding var openSession: Bool
    @Binding var workspaceButtonX: CGFloat
    @State private var plus = false
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: gap) {
            row
        }
        .underOverview(pages)
        .overlay(alignment: .trailing) {
            if pages.overview {
                IconButton(symbol: "xmark", help: "Close Overview", key: .overview) { pages.toggleOverview() }
                    .accessibilityIdentifier("overview.close")
                    .underOverview(pages, own: true)
            }
        }
        .padding(.leading, Self.inset(fullScreen: fullScreen))
        .padding(.trailing, gap)
        .frame(height: Self.height)
        .foregroundStyle(look.chrome)
        .background { Color.clear.contentShape(.rect).gesture(WindowDragGesture()) }
    }

    @ViewBuilder private var row: some View {
        HStack(spacing: gap) {
            // `rectangle.leftthird.inset.filled` alone draws too thin a bar at 13 pt to tell open and closed apart.
            IconButton(symbol: "sidebar.left", help: "Toggle Sidebar", key: .toggleSidebar) { sidebar.toggle() }
                .overlay {
                    if sidebar {
                        Image(systemName: "rectangle.leftthird.inset.filled").font(.body.weight(.medium))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("titlebar.sidebar")
                .accessibilityValue(sidebar ? "open" : "closed")
            MachineButton(pages: pages, openSession: $openSession)
        }
        .frame(width: sidebar ? sidebarWidth - Self.inset(fullScreen: fullScreen) - gap : nil,
               alignment: .leading)
        if !sidebar, let workspace = page.selectedWorkspace {
            Capped(width: 260) {
                WorkspaceButton(page: page, workspace: workspace.label, open: $workspaceMenu)
            }
            .layoutPriority(1)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: {
                workspaceButtonX = $0
            }
        }
        if page.store.state == .live || page.store.reconnecting,
           let workspace = page.selectedWorkspace
        {
            TabBar(workspace: workspace, page: page, plus: plus)
                // Made anew per session: herdr's ids repeat across sessions ("w1:t1").
                .id(page.id)
        } else {
            Spacer(minLength: 0)
        }
        IconButton(symbol: "square.grid.2x2", help: "Show Overview", key: .overview) { pages.toggleOverview() }
            .accessibilityIdentifier("titlebar.overview")
        IconButton(symbol: "command", help: "Command Palette", key: .palette) { palette.toggle() }
            .accessibilityIdentifier("titlebar.palette")
        IconButton(symbol: "plus", help: "New Tab", key: .newTab) { Task { await page.newTab() } }
            .disabled(page.selectedWorkspace == nil || page.store.state != .live)
            .accessibilityIdentifier("titlebar.new-tab")
            .overlay {
                if plus, page.dragging != nil {
                    DropIndicator(radius: 7)
                }
            }
            .onDrop(of: page.selectedWorkspaceID == nil ? [] : [.ovviDrag], delegate: PaneDrop(
                page: page, target: .move(.newTab(workspaceID: page.selectedWorkspaceID ?? "")), over: $plus,
            ))
            .clearsDrop(page) { plus = false }
    }
}

private struct MachineButton: View {
    let pages: WindowPages
    @Binding var openSession: Bool

    var body: some View {
        let current = pages.machine
        Menu {
            // macOS 27 draws no images in these menus (an AppKit NSMenuItem.image does not show either); the icons are
            // here for systems that do.
            ForEach(MachineList.shared.all) { machine in
                Toggle(isOn: Binding { machine == current } set: { _ in
                    guard machine != current else { return }
                    if let window = WindowPages.windows.first(where: { $0.machine == machine }) {
                        window.window?.makeKeyAndOrderFront(nil)
                    } else {
                        WindowPages.open(machine: machine)
                    }
                }) { Label(machine.name, systemImage: machine.icon) }
            }
            Divider()
            Button("Open Session…", systemImage: "plus.square.on.square") { openSession = true }
            Divider()
            Button("Add Machine…", systemImage: "plus") {
                SettingsRoute.shared.open(.machines, .machine(MachinePage.new))
            }
            Button("Edit Machines…", systemImage: "pencil") { SettingsRoute.shared.open(.machines) }
        } label: {
            Image(systemName: current.icon).fontWeight(.medium)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChromeStyle(radius: 7))
        .fixedSize()
        .help("Machine")
        .accessibilityLabel("Machine: \(current.name)")
        .accessibilityValue(current.icon)
        .accessibilityIdentifier("titlebar.machine")
    }
}

private struct WorkspaceButton: View {
    let page: Page
    let workspace: String
    @Binding var open: Bool
    @State private var over = false
    @State private var spring: Task<Void, Never>?
    @Environment(\.look) private var look

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").fontWeight(.medium)
                Capped(width: 110) { Text(page.store.title).lineLimit(1) }.layoutPriority(1)
                Rectangle().fill(look.divider).frame(width: 1, height: 12)
                FadeText(text: Text(workspace)).foregroundStyle(look.selected)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .frame(height: 28)
        }
        .buttonStyle(ChromeStyle(selected: open, radius: 7))
        .overlay {
            if over, page.dragging != nil {
                DropIndicator(radius: 7)
            }
        }
        .onDrop(of: [.ovviDrag], delegate: SpringDrop(page: page, over: $over, spring: $spring) { open = true })
        .clearsDrop(page) {
            spring?.cancel()
            over = false
        }
        .onDisappear { spring?.cancel() }
        .accessibilityIdentifier("titlebar.workspace")
        .help("Space")
        .accessibilityLabel("Space")
        .accessibilityValue("\(page.store.title) | \(workspace)")
    }
}

/// Offers its view at most `width` and takes the view's own size: a `frame(maxWidth:)` takes the whole offer.
private struct Capped: Layout {
    let width: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let offer = ProposedViewSize(width: min(proposal.width ?? width, width), height: proposal.height)
        return subviews.first?.sizeThatFits(offer) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

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
