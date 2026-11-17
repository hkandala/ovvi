import HerdrKit
import SwiftUI

/// Under Archived Sessions: the agents' summary, which opens the Agents panel, then Keyboard Shortcuts, Command
/// Palette, a line and Settings.
struct SidebarFoot: View {
    static let height: CGFloat = 28

    let pages: WindowPages
    @Binding var panel: WindowPanel?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            AgentsSummary(stores: pages.machineStores, open: panel == .agents) { panel = .agents }
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
            .padding(.horizontal, 8).frame(height: 22)
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

/// The agents of every session attached on this window's machine that need you or finished unseen, newest change
/// first in each group. A pick shows its tab, in whichever window has its session, as a notification's click does.
struct AgentsPanel: View {
    let pages: WindowPages
    /// The window's: the list stays under the title row.
    let height: CGFloat
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let groups = [AgentState.needsYou, .finishedUnseen].map { state in
            (state, pages.machineStores.flatMap { store in
                // Pane ids repeat across sessions.
                store.agentPanes.filter { $0.state == state }.map { (id: "\(store.session) \($0.id)", store, $0) }
            }.sorted { $0.2.since ?? .distantPast > $1.2.since ?? .distantPast })
        }.filter { !$0.1.isEmpty }
        VStack(alignment: .leading, spacing: 2) {
            Text("Agents · \(pages.machine.name)").font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 2)
                .accessibilityIdentifier("agents.panel.header")
            if groups.isEmpty {
                VStack(spacing: 4) {
                    Text("All caught up").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    Text("Agents that need you or finish show here.").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 18)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("agents.panel.empty")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.0) { state, rows in
                            if state != groups[0].0 {
                                Divider().padding(.horizontal, 8).padding(.vertical, 6)
                            }
                            Text("\(state.title) · \(rows.count)").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
                                .accessibilityIdentifier("agents.panel.group.\(state.title)")
                            ForEach(rows, id: \.id) { row($0.1, $0.2) }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .fadesScrolledEdges()
                .frame(maxHeight: max(0, min(440, height - TitleBar.height - 100)))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(width: 320, alignment: .leading)
        .floatingGlass(in: .rect(cornerRadius: 12))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agents.panel")
    }

    private func row(_ store: HostStore, _ pane: HostStore.Pane) -> some View {
        let title = pane.agentTitle ?? "agent"
        let place = [store.title, store.workspace(of: pane.tabID)?.label].compactMap(\.self).joined(separator: " · ")
        return Button {
            close()
            WindowPages.go(to: Notifications.id(pane, of: store))
        } label: {
            HStack(alignment: .top, spacing: 8) {
                ProgramTile(icon: pane.iconID, letter: pane.letter).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .medium)).frame(height: 18)
                    Text(place).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.top, 7)
            .frame(height: 48, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(ChromeStyle(radius: 10))
        .accessibilityLabel("\(title), \(place)")
        .accessibilityValue(pane.state?.title ?? "")
        .accessibilityIdentifier("agents.panel.\(store.session).\(pane.id)")
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
