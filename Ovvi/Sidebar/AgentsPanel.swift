import HerdrKit
import SwiftUI

/// The agents of every session attached on this window's machine that need you or finished unseen, newest change
/// first in each group. A pick shows its tab, in whichever window has its session, as a notification's click does.
/// Clear All and a done row's × mark finishes seen, as a look at them does.
struct AgentsPanel: View {
    let pages: WindowPages
    /// The window's: the list stays under the title row.
    let height: CGFloat
    let width: CGFloat
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
            Text("Agents · \(pages.machine.name)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
                .accessibilityIdentifier("agents.panel.header")
            if groups.isEmpty {
                Text("All caught up").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 18).padding(.bottom, 14)
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("agents.panel.group.\(state.title)")
                                .overlay(alignment: .trailing) {
                                    if state == .finishedUnseen {
                                        // Its text on the rows' right edge, as the heading's is on their left.
                                        clearAll.padding(.trailing, -6)
                                    }
                                }
                                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
                            ForEach(rows, id: \.id) { AgentRow(store: $0.1, pane: $0.2, close: close) }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.never)
                .fadesScrolledEdges()
                .frame(maxHeight: max(0, min(440, height - TitleBar.height - 100)))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The text 16 pt from each edge.
        .padding([.horizontal, .top], 8).padding(.bottom, 7.5)
        .frame(width: width, alignment: .leading)
        .floatingGlass(in: .rect(cornerRadius: 12), material: nil)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agents.panel")
    }

    private var clearAll: some View {
        Button {
            for store in pages.machineStores {
                store.clear(store.agentPanes.filter { $0.state == .finishedUnseen })
            }
        } label: {
            Text("Clear All").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).frame(height: 20)
        }
        .buttonStyle(ChromeStyle(radius: 6))
        .accessibilityIdentifier("agents.panel.clearAll")
    }
}

/// Lit as the palette's rows are under the pointer; a done one shows its × there.
private struct AgentRow: View {
    let store: HostStore
    let pane: HostStore.Pane
    let close: () -> Void
    @State private var hovering = false

    var body: some View {
        let title = pane.agentTitle ?? "agent"
        let place = [store.title, store.workspace(of: pane.tabID)?.label].compactMap(\.self).joined(separator: " · ")
        let clears = pane.state == .finishedUnseen
        Button {
            close()
            WindowPages.go(to: Notifications.id(pane, of: store))
        } label: {
            HStack(alignment: .top, spacing: 8) {
                ProgramTile(icon: pane.iconID, letter: pane.letter).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .medium)).frame(height: 18)
                    Text(place).font(.system(size: 11)).foregroundStyle(
                        hovering ? AnyShapeStyle(Look.onAccent.opacity(0.75)) : AnyShapeStyle(.secondary),
                    )
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovering ? AnyShapeStyle(Look.onAccent) : AnyShapeStyle(.primary))
            .padding(.leading, 8).padding(.trailing, clears && hovering ? 32 : 8).padding(.top, 7)
            .frame(height: 48, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(ChromeStyle(selected: hovering, radius: 8, tint: .accentColor))
        .accessibilityLabel("\(title), \(place)")
        .accessibilityValue(pane.state?.title ?? "")
        .accessibilityAddTraits(hovering ? .isSelected : [])
        .accessibilityActions {
            if clears {
                Button("Clear") { store.clear([pane]) }
            }
        }
        .accessibilityIdentifier("agents.panel.\(store.session).\(pane.id)")
        .overlay(alignment: .trailing) {
            if clears, hovering {
                Button {
                    store.clear([pane])
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Look.onAccent)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(ChromeStyle(radius: 6))
                .padding(.trailing, 8)
                .accessibilityLabel("Clear")
                .accessibilityIdentifier("agents.panel.clear.\(store.session).\(pane.id)")
            }
        }
        .onHover { hovering = $0 }
    }
}
