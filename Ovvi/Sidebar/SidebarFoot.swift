import HerdrKit
import SwiftUI

/// Under Archived Sessions: the agents' summary, which opens the Agents panel, then Keyboard Shortcuts, Command
/// Palette, a line and Settings.
struct SidebarFoot: View {
    static let box: CGFloat = 22
    private static let height: CGFloat = 28
    /// The box's left edge from the window's, on Archived Sessions' text; its bottom sits as far over the window's.
    static let inset = Sidebar.rowInsets.leading + WorkspaceRow.textInset
    private static let end: CGFloat = 4

    /// The Agents panel's: from the box's left edge to the gear's right edge.
    static func width(sidebar: Double) -> CGFloat {
        sidebar - gap - Sidebar.rowInsets.trailing - end - inset
    }

    let pages: WindowPages
    @Binding var panel: WindowPanel?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            AgentsSummary(stores: pages.machineStores, open: panel == .agents) { panel = .agents }
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
        // The gear's ink right-aligned with Archived Sessions' chevron.
        .padding(.trailing, Self.end)
        // The sidebar ends gap over the window's bottom.
        .padding(.bottom, Self.inset - gap - (Self.height - Self.box) / 2)
    }
}

/// The state box with words: who needs you, else the unseen finishes, else who works, else "All caught up".
private struct AgentsSummary: View {
    let stores: [HostStore]
    let open: Bool
    let action: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        var counts: [AgentState: Int] = [:]
        for store in stores {
            counts.merge(store.stateCounts, uniquingKeysWith: +)
        }
        let order: [AgentState] = [.needsYou, .finishedUnseen, .working, .idle]
        let state = order.dropLast().first { counts[$0, default: 0] > 0 }
        let words = state.map { Self.words(counts[$0, default: 0], $0) } ?? "All caught up"
        let all = order.compactMap { state in counts[state].map { Self.words($0, state) } }
        let color = state?.color(look) ?? .secondary, shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 5) {
                if let state {
                    StateIcon(state: state)
                }
                Text(words)
            }
            .lineLimit(1)
            .font(.system(size: 11, weight: state == nil ? .medium : .semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).frame(height: SidebarFoot.box)
            .background(color.opacity(state == nil ? 0 : open ? 0.24 : 0.14), in: shape)
            .overlay(shape.strokeBorder(state == nil ? look.divider : color.opacity(0.45)))
        }
        .buttonStyle(ChromeStyle(radius: 6))
        .tip(all.isEmpty ? "No agents" : all.joined(separator: " · "))
        .accessibilityLabel("Agents")
        .accessibilityValue(words)
        .accessibilityIdentifier("sidebar.agents")
    }

    static func words(_ count: Int, _ state: AgentState) -> String {
        switch state {
        case .needsYou: count == 1 ? "1 needs you" : "\(count) need you"
        case .finishedUnseen: "\(count) done"
        case .working: "\(count) working"
        case .idle: "\(count) idle"
        }
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
