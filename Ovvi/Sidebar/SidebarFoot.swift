import HerdrKit
import SwiftUI

/// The agents' box, which opens the agents section, then Keyboard Shortcuts, Command Palette, a line and Settings.
struct SidebarFoot: View {
    static let box: CGFloat = 22
    private static let height: CGFloat = 28
    /// The box's left edge from the window's, on the agents section's text; its bottom sits as far over the window's.
    private static let inset = Sidebar.rowInsets.leading + WorkspaceRow.textInset
    /// The gear's ink ends on the section's right column: its archive button's, the fold chevrons', a row's ×.
    private static let end: CGFloat = 1.5

    let pages: WindowPages
    @Binding var panel: WindowPanel?
    let open: Bool
    let toggle: () -> Void
    @Environment(\.openWindow) private var openWindow
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            AgentsBox(counts: pages.machineStores.stateCounts, open: open, action: toggle)
                .layoutPriority(1)
            Spacer(minLength: gap)
            IconButton(symbol: "keyboard", help: "Keyboard Shortcuts", key: .hotkey("app.shortcuts")) {
                panel = .shortcuts
            }
            .accessibilityIdentifier("sidebar.shortcuts")
            IconButton(symbol: "command", help: "Command Palette", key: .hotkey("app.palette")) { panel = .palette }
                .accessibilityIdentifier("sidebar.palette")
            Rectangle().fill(look.divider).frame(width: 1, height: 14).padding(.horizontal, 6)
            IconButton(symbol: "gearshape", help: "Settings", key: .hotkey("app.settings")) {
                openWindow(id: WindowPages.settingsScene)
            }
            .accessibilityIdentifier("sidebar.settings")
        }
        .frame(height: Self.height)
        .padding(.leading, WorkspaceRow.textInset)
        .padding(.trailing, Self.end)
        // The sidebar ends gap over the window's bottom.
        .padding(.bottom, Self.inset - gap - (Self.height - Self.box) / 2)
    }
}

/// The state box with words: who needs you, else the unseen finishes, else who works; else the agents' symbol.
private struct AgentsBox: View {
    let counts: [AgentState: Int]
    let open: Bool
    let action: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        let state = AgentState.footOrder.dropLast().first { counts[$0, default: 0] > 0 }
        let all = AgentState.footOrder.compactMap { state in counts[state].map { state.words($0) } }
        return Button(action: action) {
            label(state).frame(height: SidebarFoot.box)
        }
        .buttonStyle(ChromeStyle(radius: 6))
        .tip(all.isEmpty ? "No agents" : all.joined(separator: " · "))
        .accessibilityLabel("Agents")
        .accessibilityValue(state.map { $0.words(counts[$0, default: 0]) } ?? "All caught up")
        .accessibilityAddTraits(open ? .isSelected : [])
        .accessibilityIdentifier("sidebar.agents")
    }

    @ViewBuilder private func label(_ state: AgentState?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if let state {
            let color = state.color(look)
            HStack(spacing: 5) {
                StateIcon(state: state)
                Text(state.words(counts[state, default: 0]))
            }
            .lineLimit(1)
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
            .background(color.opacity(open ? 0.24 : 0.14), in: shape)
            .overlay(shape.strokeBorder(color.opacity(0.45)))
        } else {
            Image(systemName: "sparkles").font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
                .frame(width: SidebarFoot.box, height: SidebarFoot.box)
                .background(.primary.opacity(open ? 0.08 : 0), in: shape)
                .overlay(shape.strokeBorder(look.divider))
        }
    }
}

extension AgentState {
    /// The foot's, the tooltip's and the section's order.
    static let footOrder: [AgentState] = [.needsYou, .finishedUnseen, .working, .idle]

    func words(_ count: Int) -> String {
        switch self {
        case .needsYou: count == 1 ? "1 needs you" : "\(count) need you"
        case .finishedUnseen: "\(count) done"
        case .working: "\(count) working"
        case .idle: "\(count) idle"
        }
    }
}

extension [HostStore] {
    var stateCounts: [AgentState: Int] {
        reduce(into: [:]) { counts, store in counts.merge(store.stateCounts, uniquingKeysWith: +) }
    }
}

extension WindowPages {
    /// The sessions attached in any window on this window's machine.
    var machineStores: [HostStore] {
        HostStore.all.filter { store in
            store.machine.id == machine.id && store.windows.contains { $0.page(store) != nil }
        }
    }
}
