import HerdrKit
import SwiftUI

/// The agents' box, which opens the agents section, then Keyboard Shortcuts, Command Palette, a line and Settings.
struct SidebarFoot: View {
    fileprivate static let box: CGFloat = 22
    private static let height: CGFloat = 28
    /// The box sits as far under the agents section's border as over the window's bottom.
    private static let margin: CGFloat = 18
    /// The box's left edge on the agents section's text column.
    private static let leading = AgentsSection.inset + AgentsSection.padding
    /// The gear's ink ends on the section's right column: its archive button's, the fold chevrons', a row's ×.
    private static let end: CGFloat = 5

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
        .padding(.leading, Self.leading)
        .padding(.trailing, Self.end)
        .padding(.top, Self.margin - (Self.height - Self.box) / 2)
        // The sidebar ends gap over the window's bottom.
        .padding(.bottom, Self.margin - gap - (Self.height - Self.box) / 2)
    }
}

/// The state box with words: who needs you, else the unseen finishes, else who works; else the agents' symbol and
/// "Agents".
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
        .tip(all.isEmpty ? "No agents running" : all.joined(separator: " · "))
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
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                Text("Agents")
            }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
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
