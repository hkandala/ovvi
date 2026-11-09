import HerdrKit
import SwiftUI

/// A workspace: its name, and its branch with ahead and behind on a second line in a repository; its state's icon and,
/// when it runs agents, a chevron at the end. Unfolded, its agents follow, one line each, inside the row's glass
/// (selected) or its border (the others) (ui/window#space-rows). A linked worktree sits indented under its
/// repository's row, on a guide line.
struct WorkspaceRow: View {
    /// The text's inset in a row; the page header's text lines up.
    static let textInset: CGFloat = 8
    /// Between two rows.
    static let gap: CGFloat = 10

    let workspace: HostStore.Workspace
    let parent: HostStore.Workspace?
    let page: Page
    /// A worktree row follows: the guide line starts under this row.
    let guideBelow: Bool
    /// The first and the last group's workspace: they cannot move up or down.
    let ends: (first: String?, last: String?)
    /// Its agent panes as shown, newest change first; empty: no chevron.
    var agents: [HostStore.Pane] = []
    /// It runs agents: a chevron.
    var hasAgents = false
    /// Unfolded: its agents show.
    var open = false
    /// Nil while the filter holds it open.
    var fold: (() -> Void)?
    @State private var renaming = false
    @Environment(\.look) private var look

    var body: some View {
        let selected = workspace.id == page.selectedWorkspaceID
        let state = workspace.state
        // The icon: not while idle, nor under the rename field.
        let shown = state == .idle || renaming ? nil : state
        let height: CGFloat = workspace.git == nil ? 30 : 44
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) {
            header(selected: selected, shown: shown, height: height)
            if open {
                VStack(spacing: 0) {
                    ForEach(agents) { AgentLine(pane: $0, page: page) }
                }
                .padding([.horizontal, .bottom], 4)
            }
        }
        // The selected row's glass, over its agents too; the others' border, folded or not, and no glass.
        .background {
            if selected {
                Pill(shape: shape)
            } else {
                shape.strokeBorder(.primary.opacity(0.14))
            }
        }
        .padding(.leading, parent == nil ? 0 : 14)
        // In the gap under a repository's row or a worktree's that another worktree follows, where the next row's
        // top border starts its straight part (14 pt indent and 10 pt corner): the rows' borders carry it on.
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
            // AppKit's double-click, counted from the events' times: SwiftUI's TapGesture(count: 2) missed one
            // while the app was busy drawing the first click's selection.
            if let event = NSApp.currentEvent, event.type == .leftMouseUp, event.clickCount == 2 {
                startRenaming()
            }
        } label: {
            label(selected: selected, state: state, git: git)
                // The state icon's and the chevron's room (`stateIcon`, `chevron`).
                .padding(.leading, Self.textInset)
                .padding(.trailing, 8 + (shown == nil ? 0 : 12 + 8) + (hasAgents ? Self.chevron + 6 : 0))
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        }
        // The row's glass is the whole row's (`body`); under the pointer only an unselected one fills.
        .buttonStyle(ChromeStyle(radius: 10, hovered: selected ? false : nil))
        .dragSource(.workspace(workspace.id), page: page)
        .accessibilityIdentifier("workspace.\(workspace.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue([state?.word, git.map { "\($0.branch) ahead \($0.ahead) behind \($0.behind)" },
                             parent.map { "worktree of \($0.label)" }].compactMap(\.self).joined(separator: ", "))
        .overlay(alignment: .topTrailing) { stateIcon(shown).padding(.trailing, hasAgents ? Self.chevron + 6 : 0) }
        .overlay(alignment: .topTrailing) { chevron }
        .overlay(alignment: .leading) {
            if renaming {
                // Enter: herdr's label; the snapshot after it shows it.
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
        // Writes only while the session runs: a stopped one keeps its last rows.
        .contextMenu { menu.disabled(page.store.state != .live) }
    }

    /// The name, and the branch line in a repository.
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

    /// The chevron's width.
    private static let chevron: CGFloat = 12

    /// Folds or unfolds the agents, at the end of the name's line; none without agents. Its own button: a click on the
    /// row selects it.
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

    /// The state's icon (12 pt, as a tab's) at the end of the name's line; nothing with no agent. Over
    /// the button, so a test sees it; the row's value has the state word for VoiceOver.
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
        // A worktree moves with its repository's row.
        Button("Move Up") { store.move(workspace: workspace.id, by: -1) }
            .disabled(parent != nil || first)
        Button("Move Down") { store.move(workspace: workspace.id, by: 1) }
            .disabled(parent != nil || last)
        // Only where the row shows a branch: the same repository.
        if workspace.git != nil {
            Divider()
            Button("Fetch") { Task { await store.sync(workspace, .fetch) } }
            Button("Pull") { Task { await store.sync(workspace, .pull) } }
            Button("Push") { Task { await store.sync(workspace, .push) } }
        }
        Divider()
        Button("Close Space") { page.close(.workspace(workspace.id)) }
    }

    /// Not while the session is stopped (a double-click too): the rename would fail.
    private func startRenaming() {
        guard page.store.state == .live else { return }
        renaming = true
    }

    /// The keyboard goes back to the selected tab's card.
    private func stopRenaming() {
        guard renaming else { return }
        renaming = false
        page.focusKeyboardCard()
    }
}

/// An agent in its workspace's unfolded row (ui/window#agent-rows), one line: its program tile, its title (an
/// untitled session's first prompt, cut at the row's width), then its state box with the working time. A click goes to
/// its tab and pane; lit while it is the shown tab's keyboard card.
struct AgentLine: View {
    let pane: HostStore.Pane
    let page: Page
    @Environment(\.look) private var look

    var body: some View {
        let state = pane.state ?? .idle
        let lit = page.keyboardCard(page.selectedTab?.id) === pane
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
        .buttonStyle(ChromeStyle(selected: lit, radius: 7, tint: .primary.opacity(0.08)))
        .accessibilityIdentifier("agent.\(pane.id)")
        .accessibilityLabel("\(title), \(page.place(pane))")
        .accessibilityValue(pane.state?.title ?? "")
        .accessibilityAddTraits(lit ? .isSelected : [])
        .hoverPanel(place: .beside) { close in HoverCard(tabID: pane.tabID, page: page, close: close) }
    }
}
