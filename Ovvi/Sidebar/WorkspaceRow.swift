import HerdrKit
import SwiftUI

struct WorkspaceRow: View, Equatable {
    static let textInset: CGFloat = 8
    static let gap: CGFloat = 10

    let workspace: HostStore.Workspace
    let parent: HostStore.Workspace?
    let page: Page
    let frames: SidebarPage.RowFrames
    let guideBelow: Bool
    let ends: (first: String?, last: String?)
    let agents: [HostStore.Pane]
    let hasAgents: Bool
    let fold: (() -> Void)?
    @State private var renaming = false
    @Environment(\.look) private var look

    /// `fold` is a new closure each time: compared, every page update would make the rows in view again. What the row
    /// reads from the store it observes itself.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.workspace === rhs.workspace && lhs.parent === rhs.parent && lhs.page === rhs.page
            && lhs.frames === rhs.frames && lhs.guideBelow == rhs.guideBelow && lhs.ends == rhs.ends
            && lhs.hasAgents == rhs.hasAgents && (lhs.fold == nil) == (rhs.fold == nil)
            && lhs.agents.elementsEqual(rhs.agents, by: ===)
    }

    var body: some View {
        let _ = Latency.madeRow() // swiftlint:disable:this redundant_discardable_let
        let selected = workspace.id == page.selectedWorkspaceID
        let state = workspace.state
        let shown = renaming ? nil : state?.shown
        let height: CGFloat = workspace.git == nil ? 30 : 44
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) {
            header(selected: selected, shown: shown, height: height)
            if open {
                VStack(spacing: 0) {
                    ForEach(agents) { AgentLine(pane: $0, page: page, frames: frames) }
                }
                .padding([.horizontal, .bottom], 4)
            }
        }
        .background {
            if selected {
                Pill(shape: shape)
            } else {
                shape.strokeBorder(.primary.opacity(0.14))
            }
        }
        .padding(.leading, parent == nil ? 0 : 14)
        .background(alignment: .topLeading) {
            if guideBelow {
                GeometryReader { geometry in
                    // 1 pt on, into the next row's border: a continuous corner turns straight just past 10 pt.
                    Rectangle().fill(.separator).frame(width: 1, height: Self.gap + 1)
                        .offset(x: 24, y: geometry.size.height)
                }
            }
        }
    }

    private func header(selected: Bool, shown: AgentState?, height: CGFloat) -> some View {
        let git = workspace.git
        let state = workspace.state
        return Button {
            page.select(workspace)
            if NSApp.isDoubleClick {
                startRenaming()
            }
        } label: {
            label(selected: selected, state: state, git: git)
                .padding(.leading, Self.textInset)
                .padding(.trailing, 8 + (shown == nil ? 0 : 12 + 8) + (hasAgents ? Self.chevron + 6 : 0))
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        }
        .buttonStyle(ChromeStyle(radius: 10, hovered: selected ? false : nil, light: frames.light(workspace.id)))
        .target(workspace.id, in: frames)
        .dragSource(.workspace(workspace.id), page: page)
        .accessibilityIdentifier("workspace.\(workspace.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue([state?.word, git.map { "\($0.branch) ahead \($0.ahead) behind \($0.behind)" },
                             parent.map { "worktree of \($0.label)" }].compactMap(\.self).joined(separator: ", "))
        .overlay(alignment: .topTrailing) { stateIcon(shown).padding(.trailing, hasAgents ? Self.chevron + 6 : 0) }
        .overlay(alignment: .topTrailing) { chevron }
        .overlay(alignment: .leading) {
            if renaming {
                RenameField(prompt: "Space Name", initial: workspace.label, commit: { label in
                    Task { await page.store.rename(workspace: workspace.id, label: label) }
                }, end: stopRenaming)
                    .font(.system(size: 13))
                    .padding(.leading, Self.textInset)
                    .padding(.trailing, 8)
                    .frame(height: 30, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .accessibilityIdentifier("workspace.\(workspace.id).rename")
            }
        }
        .contextMenu { menu.disabled(page.store.state != .live) }
    }

    private func label(selected: Bool, state: AgentState?, git: GitStatus?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(workspace.label).font(.system(size: 13, weight: state?.calls == true ? .medium : .regular))
                    .lineLimit(1).opacity(renaming ? 0 : 1)
                    .foregroundStyle(selected ? look.selected : look.chrome)
                Spacer(minLength: 0)
            }
            if let git {
                HStack(spacing: 4) {
                    Image(symbol: "source.branch").font(.system(size: 10))
                    Text(git.branch).lineLimit(1).truncationMode(.middle)
                    if git.ahead > 0 {
                        Text("↑\(git.ahead)").foregroundStyle(look.finished)
                    }
                    if git.behind > 0 {
                        Text("↓\(git.behind)").foregroundStyle(look.error)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var open: Bool {
        !agents.isEmpty
    }

    private static let chevron: CGFloat = 12

    @ViewBuilder private var chevron: some View {
        if hasAgents, !renaming {
            Button { fold?() } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: Self.chevron + 8, height: 22).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(fold == nil)
            .frame(height: 30)
            .padding(.trailing, 4)
            .help(open ? "Hide Agents" : "Show Agents")
            .accessibilityLabel(open ? "Hide Agents" : "Show Agents")
            .accessibilityValue(open ? "expanded" : "collapsed")
            .accessibilityIdentifier("fold.\(workspace.id)")
        }
    }

    /// Over the button, so a test sees it; the row's value has the state word for VoiceOver.
    @ViewBuilder
    private func stateIcon(_ state: AgentState?) -> some View {
        if let state {
            StateIcon(state: state).stateElement(state, "workspace.\(workspace.id).state")
                .frame(height: 30).padding(.trailing, 8).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var menu: some View {
        let store = page.store
        let first = ends.first == workspace.id, last = ends.last == workspace.id
        Button("New Tab") { Task { await page.newTab(in: workspace) } }
        Button("Rename Space") { startRenaming() }
        Button("Move Up") { store.move(workspace: workspace.id, by: -1) }
            .disabled(parent != nil || first)
        Button("Move Down") { store.move(workspace: workspace.id, by: 1) }
            .disabled(parent != nil || last)
        if workspace.git != nil {
            Divider()
            Button("Fetch") { Task { await store.sync(workspace, .fetch) } }
            Button("Pull") { Task { await store.sync(workspace, .pull) } }
            Button("Push") { Task { await store.sync(workspace, .push) } }
        }
        Divider()
        Button("Close Space") { page.close(.workspace(workspace.id)) }
    }

    private func startRenaming() {
        guard page.store.state == .live else { return }
        renaming = true
    }

    private func stopRenaming() {
        guard renaming else { return }
        renaming = false
        page.focusKeyboardCard()
    }
}

struct AgentLine: View {
    let pane: HostStore.Pane
    let page: Page
    let frames: SidebarPage.RowFrames
    @Environment(\.look) private var look

    var body: some View {
        let _ = Latency.madeRow() // swiftlint:disable:this redundant_discardable_let
        let state = pane.state ?? .idle
        let lit = page.keyboardCard(page.selectedTab?.id) === pane
        let light = frames.light(pane.id)
        let title = pane.agentTitle ?? "agent"
        Button { page.go(to: pane) } label: {
            HStack(spacing: 8) {
                ProgramTile(icon: pane.iconID, letter: pane.letter)
                Text(title).font(.system(size: 13, weight: state.calls ? .medium : .regular)).lineLimit(1)
                    .foregroundStyle(lit ? look.selected : look.chrome)
                Spacer(minLength: 0)
                if state != .idle {
                    StateBox(state: state, since: state == .working ? pane.since : nil)
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 28)
        }
        .buttonStyle(ChromeStyle(selected: lit, radius: 7, tint: .primary.opacity(0.08), light: light))
        .target(pane.id, in: frames)
        .accessibilityIdentifier("agent.\(pane.id)")
        .accessibilityLabel("\(title), \(page.place(pane))")
        .accessibilityValue(pane.state?.title ?? "")
        .accessibilityAddTraits(lit ? .isSelected : [])
        .hoverPanel(place: .beside, light: light) { close in HoverCard(tabID: pane.tabID, page: page, close: close) }
    }
}

private extension View {
    func target(_ id: String, in frames: SidebarPage.RowFrames) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rows")) } action: {
            frames.targets[id] = $0
            // Moved under a still pointer: a snapshot, a fold, the filter.
            frames.aim()
        }
        .onDisappear {
            frames.targets[id] = nil
            frames.aim()
        }
    }
}
