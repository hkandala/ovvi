import HerdrKit
import SwiftUI

struct TabButton: View {
    let tab: HostStore.Tab
    let workspace: HostStore.Workspace
    let page: Page
    let hovering: Bool
    let clicked: () -> Void
    @State private var renaming = false
    @State private var announcement: String?
    @State private var announcing: Task<Void, Never>?
    @State private var bounces = 0
    @Environment(\.look) private var look

    var body: some View {
        let selected = workspace.id == page.selectedWorkspaceID && tab.id == page.selectedTabIDs[workspace.id]
        let stack = page.stack(tab)
        let agent = tab.agent, state = agent?.state?.shown
        Button {
            clicked()
            page.select(workspace, tab: tab.id)
            if NSApp.isDoubleClick {
                renaming = true
            }
        } label: {
            HStack(spacing: 10) {
                IconStack(panes: stack)
                    .keyframeAnimator(initialValue: 1.0, trigger: Animation.reduced ? 0 : bounces) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.15, duration: 0.15)
                        SpringKeyframe(1, duration: 0.3)
                    }
                FadeText(text: announcement.flatMap { selected ? nil : Text($0) } ?? page.titleLabel(tab))
                    .opacity(renaming ? 0 : 1)
                    .foregroundStyle(selected ? look.selected : look.chrome)
            }
            .padding(.leading, 11)
            .padding(.trailing, hovering && !renaming || state != nil ? 28 : 12)
            .frame(width: TabBar.width, height: TabBar.height, alignment: .leading)
        }
        .buttonStyle(ChromeStyle(radius: TabBar.radius, inset: TabBar.inset, hovered: hovering))
        .dragSource(.tab(tab.id), page: page)
        .accessibilityIdentifier("tab.\(tab.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue([agent.flatMap { agent in
            agent.state == .idle ? nil : "\(agent.agentName ?? "agent"), \(agent.state?.word ?? "")"
        }, "icons: " + stack.map(\.iconID).joined(separator: ", ")].compactMap(\.self).joined(separator: "; "))
        .accessibilityAction(named: "Close Tab") { page.close(.tab(tab.id)) }
        .hoverPanel(place: .under, action: "Show Panes") { close in
            HoverCard(tabID: tab.id, page: page, close: close)
        }
        // Over the button, after the icons: in the button's label it cannot take the keyboard.
        .overlay(alignment: .leading) {
            if renaming {
                RenameField(prompt: "Tab Name", initial: tab.label, commit: { label in
                    Task { await page.store.rename(tab: tab.id, label: label) }
                }, end: stopRenaming)
                    .padding(.leading, 11 + IconStack.width(stack.count) + 10)
                    .padding(.trailing, 8)
                    .accessibilityIdentifier("tab.\(tab.id).rename")
            }
        }
        .overlay(alignment: .trailing) {
            if let state, !hovering, !renaming {
                StateIcon(state: state).padding(.trailing, 11).stateElement(state, "tab.\(tab.id).state")
            }
        }
        .overlay(alignment: .trailing) {
            if hovering, !renaming {
                Button { page.close(.tab(tab.id)) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(ChromeStyle(radius: 11))
                .help("Close Tab")
                .accessibilityLabel("Close Tab")
                .accessibilityIdentifier("tab.\(tab.id).close")
                .padding(.trailing, 6)
            }
        }
        .contextMenu { menu }
        .onChange(of: agent?.state) { _, new in
            guard let new, new.calls, !selected else { return }
            announce("\(agent?.agentName ?? "agent") \(new.word)")
        }
    }

    private func announce(_ text: String) {
        if !Animation.reduced {
            bounces += 1
        }
        announcement = text
        announcing?.cancel()
        announcing = Task {
            if await (try? Task.sleep(for: .seconds(3))) != nil {
                announcement = nil
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        let tabs = workspace.tabs, store = page.store
        Button("Rename Tab") { renaming = true }
        Button("Move Tab Left") { store.move(tab: tab.id, by: -1) }
            .disabled(tabs.first?.id == tab.id)
        Button("Move Tab Right") { store.move(tab: tab.id, by: 1) }
            .disabled(tabs.last?.id == tab.id)
        Divider()
        Button("Close Tab") { page.close(.tab(tab.id)) }
        Button("Close Other Tabs") { page.closeTabs(besides: tab.id, right: false) }
            .disabled(tabs.count < 2)
        Button("Close Tabs to the Right") { page.closeTabs(besides: tab.id, right: true) }
            .disabled(tabs.last?.id == tab.id)
    }

    private func stopRenaming() {
        guard renaming else { return }
        renaming = false
        page.focusKeyboardCard()
    }
}

extension Page {
    func titleLabel(_ tab: HostStore.Tab) -> Text {
        let title = title(tab)
        return Text("\(title.name)\(Text(title.folder.map { " \($0)" } ?? "").foregroundStyle(.secondary))")
    }
}
