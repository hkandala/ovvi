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
                IconButton(symbol: "xmark", help: "Close Overview", key: .hotkey("app.overview")) {
                    pages.toggleOverview()
                }
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
            IconButton(symbol: "sidebar.left", help: "Toggle Sidebar", key: .hotkey("app.sidebar")) { sidebar.toggle() }
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
            HStack(spacing: 0) {
                HistoryButton(page: page, offset: -1)
                HistoryButton(page: page, offset: 1)
            }
            .id(page.id)
            TabBar(workspace: workspace, page: page, plus: plus)
                // Made anew per session: herdr's ids repeat across sessions ("w1:t1").
                .id(page.id)
        } else {
            Spacer(minLength: 0)
        }
        IconButton(symbol: "plus", help: "New Tab", key: .hotkey("tab.new")) { Task { await page.newTab() } }
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

/// Go Back or Go Forward. A right-click, or a press held for half a second, lists the tabs that presses would step
/// through.
private struct HistoryButton: View {
    let page: Page
    let offset: Int
    @State private var pressed: Date?

    var body: some View {
        let back = offset < 0, title = back ? "Go Back" : "Go Forward", steps = page.trail(offset)
        let key = KeyboardShortcut.hotkey(back ? "tab.back" : "tab.forward")
        Button {
            let held = pressed.map { Date.now.timeIntervalSince($0) >= 0.5 } == true
            pressed = nil
            if held {
                Task { await popUp(steps) }
            } else {
                page.goInHistory(offset)
            }
        } label: {
            Image(systemName: back ? "chevron.left" : "chevron.right").fontWeight(.medium)
                .frame(width: 28, height: 28)
        }
        // Not `Menu(primaryAction:)`: on macOS 27 it takes a long press for a click.
        .buttonStyle(HeldStyle(pressed: $pressed))
        .contextMenu {
            ForEach(Array(rows(steps).enumerated()), id: \.offset) { _, row in
                Button(row.title, action: row.go)
            }
        }
        .disabled(steps.isEmpty)
        .tip(title, key: key)
        .accessibilityLabel(key.map { "\(title) \($0.glyphs)" } ?? title)
        .accessibilityIdentifier(back ? "titlebar.back" : "titlebar.forward")
    }

    /// Text only: macOS 27 draws no images in these menus. A row goes nowhere if the history changed under the open
    /// menu.
    private func rows(_ steps: [Int]) -> [(title: String, go: () -> Void)] {
        steps.compactMap { [page] index in
            let id = page.history.ids[index]
            guard let workspace = page.store.workspace(of: id), let tab = page.store.tab(id) else { return nil }
            return ("\(page.titleText(tab)) — \(workspace.label)", { page.goInHistory(to: index, id) })
        }
    }

    /// At the pointer, once the press ended.
    private func popUp(_ steps: [Int]) async {
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }
        let menu = NSMenu()
        for row in rows(steps) {
            let action = MenuAction(row.go)
            let entry = menu.addItem(withTitle: row.title, action: #selector(MenuAction.fire), keyEquivalent: "")
            entry.target = action
            entry.representedObject = action
        }
        await menu.popUp(at: view.convert(window.mouseLocationOutsideOfEventStream, from: nil), in: view)
    }
}

/// The title row's button look, and when the press began.
private struct HeldStyle: ButtonStyle {
    @Binding var pressed: Date?

    func makeBody(configuration: Configuration) -> some View {
        ChromeStyle(radius: 7).makeBody(configuration: configuration)
            .onChange(of: configuration.isPressed) { _, down in
                if down {
                    pressed = .now
                }
            }
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
        .tip("Machine")
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
        .tip("Space")
        .accessibilityLabel("Space")
        .accessibilityValue("\(page.store.title) | \(workspace)")
    }
}
