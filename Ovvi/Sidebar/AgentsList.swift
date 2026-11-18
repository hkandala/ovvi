import HerdrKit
import SwiftUI

/// The agents of every session attached on this window's machine that need you, finished unseen or work, newest
/// change first in each group; idle ones only count. A pick shows its tab, in whichever window has its session, as a
/// notification's click does. Clear All and a done row's × mark finishes seen, as a look at them does.
struct AgentsList: View {
    let pages: WindowPages
    @AppStorage(Page.foldsAndShelves, store: .sidebar) private var opened = ""

    private enum Item {
        case group(AgentState, Int)
        case agent(HostStore, HostStore.Pane)
    }

    var body: some View {
        let stores = pages.machineStores
        let groups = AgentState.footOrder.dropLast().map { state in
            (state, stores.flatMap { store in store.agentPanes.filter { $0.state == state }.map { (store, $0) } }
                .sorted { $0.1.since ?? .distantPast > $1.1.since ?? .distantPast })
        }.filter { !$0.1.isEmpty }
        // One view per element: a header beside its rows would make the lazy stack build many more.
        let items = groups.flatMap { state, rows in
            [(id: state.title, item: Item.group(state, rows.count))] + (folded(state) ? [] : rows.map { store, pane in
                // Pane ids repeat across sessions.
                (id: "\(store.session) \(pane.id)", item: Item.agent(store, pane))
            })
        }
        Summary(counts: stores.stateCounts).padding(.horizontal, AgentsSection.padding).frame(height: 26)
        Group {
            if items.isEmpty {
                EmptyState(symbol: "checkmark.circle", title: "All caught up", text: "No agent is waiting on you",
                           compact: true, id: "agents.empty")
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items, id: \.id) { item in
                            switch item.item {
                            case let .group(state, count): header(state, count)
                            case let .agent(store, pane): AgentRow(store: store, pane: pane)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .fadesScrolledEdges()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: ArchivedShelf.height)
    }

    private func folded(_ state: AgentState) -> Bool {
        opened.hasLine(pages.agentsFoldKey(state))
    }

    private func header(_ state: AgentState, _ count: Int) -> some View {
        GroupHeader(state: state, count: count, folded: folded(state)) {
            withAnimation(.fade) {
                opened = opened.togglingLine(pages.agentsFoldKey(state))
            }
        } clearAll: {
            for store in pages.machineStores {
                store.clear(store.agentPanes.filter { $0.state == .finishedUnseen })
            }
        }
    }
}

/// The counts in the foot's order, each in its state's color; where the line does not fit, the idle count goes.
private struct Summary: View {
    let counts: [AgentState: Int]
    @Environment(\.look) private var look

    var body: some View {
        let states = AgentState.footOrder.filter { counts[$0, default: 0] > 0 }
        ViewThatFits(in: .horizontal) {
            line(states).fixedSize()
            line(states.filter { $0 != .idle })
        }
        .font(.system(size: 11, weight: .medium)).lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(states.isEmpty ? "No agents running"
            : states.map { $0.words(counts[$0, default: 0]) }.joined(separator: " · "))
        .accessibilityIdentifier("agents.summary")
    }

    private func line(_ states: [AgentState]) -> some View {
        HStack(spacing: 0) {
            if states.isEmpty {
                Text("No agents running").foregroundStyle(.secondary)
            }
            ForEach(states, id: \.self) { state in
                if state != states.first {
                    Text("·").fontWeight(.regular).foregroundStyle(.secondary).padding(.horizontal, 5)
                }
                Text(state.words(counts[state, default: 0])).foregroundStyle(state.color(look))
            }
        }
    }
}

/// A click anywhere folds the group; its chevron shows under the pointer.
private struct GroupHeader: View {
    let state: AgentState
    let count: Int
    let folded: Bool
    let fold: () -> Void
    let clearAll: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: fold) {
            HStack(spacing: 6) {
                Text(state.title).font(.system(size: 11, weight: .semibold))
                Text("\(count)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 5).frame(height: 15)
                    .background(.primary.opacity(0.07), in: .capsule)
                Spacer(minLength: 0)
                if hovering {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(folded ? 0 : 90))
                        // Its ink on the section's right column, with a row's ×.
                        .frame(width: 20, height: 22).padding(.trailing, -5.5)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, AgentsSection.padding).frame(height: 24)
            .contentShape(.rect)
        }
        .buttonStyle(ChromeStyle(radius: 6, hovered: hovering))
        .accessibilityLabel(state.title)
        .accessibilityValue("\(count), \(folded ? "collapsed" : "expanded")")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("agents.group.\(state.title)")
        .overlay(alignment: .trailing) {
            if state == .finishedUnseen {
                // The header's light is its light.
                Button(action: clearAll) {
                    Text("Clear All").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).frame(height: 20).contentShape(.rect)
                }
                .buttonStyle(.plain)
                // Its ink 5.5 pt left of the right column, left of the chevron under the pointer.
                .padding(.trailing, hovering ? 19 : 4)
                .accessibilityIdentifier("agents.clearAll")
            }
        }
        .onHover { hovering = $0 }
    }
}

/// Archived Sessions' row: lit under the pointer, where a done one shows its ×.
private struct AgentRow: View {
    let store: HostStore
    let pane: HostStore.Pane
    @State private var hovering = false
    @Environment(\.look) private var look

    var body: some View {
        let title = pane.agentTitle ?? "agent"
        let place = [store.title, store.workspace(of: pane.tabID)?.label].compactMap(\.self).joined(separator: " · ")
        let clears = pane.state == .finishedUnseen
        Button {
            WindowPages.go(to: Notifications.id(pane, of: store))
        } label: {
            HStack(alignment: .top, spacing: 8) {
                ProgramTile(icon: pane.iconID, letter: pane.letter)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13)).foregroundStyle(look.chrome).frame(height: 18)
                    Text(place).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, AgentsSection.padding)
            .padding(.trailing, clears && hovering ? 16 + AgentsSection.padding : AgentsSection.padding)
            .frame(height: 48)
        }
        .buttonStyle(ChromeStyle(radius: 6))
        .accessibilityLabel("\(title), \(place)")
        .accessibilityValue(pane.state?.title ?? "")
        .accessibilityActions {
            if clears {
                Button("Clear") { store.clear([pane]) }
            }
        }
        .accessibilityIdentifier("agents.row.\(store.session).\(pane.id)")
        .overlay(alignment: .trailing) {
            if clears, hovering {
                Button {
                    store.clear([pane])
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(ChromeStyle(radius: 6))
                // Its ink as far in as the tile on the left, on the section's right column.
                .padding(.trailing, AgentsSection.padding - 4)
                .accessibilityLabel("Clear")
                .accessibilityIdentifier("agents.clear.\(store.session).\(pane.id)")
            }
        }
        .onHover { hovering = $0 }
    }
}
