import HerdrKit
import SwiftUI

/// The page's pinned tabs on top of its sidebar, above the rows that scroll (ui/window#pinned): one line each with the
/// tab's icons, its title, its workspace dimmed and its state icon; lit while it is the tab in view. At most five rows,
/// then they scroll inside. None pinned: nothing at all.
struct PinnedTabs: View {
    let page: Page
    let tabs: [HostStore.Tab]

    var body: some View {
        if !tabs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pinned").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.leading, WorkspaceRow.textInset)
                    .accessibilityAddTraits(.isHeader)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(tabs) { PinnedTab(tab: $0, page: page) }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 5 * 30)
                .fixedSize(horizontal: false, vertical: true)
                Divider().padding(.horizontal, WorkspaceRow.textInset).padding(.vertical, 4)
            }
            .padding(.leading, Sidebar.rowInsets.leading).padding(.trailing, Sidebar.rowInsets.trailing)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sidebar.pinned")
        }
    }
}

/// A pinned tab: a click shows it; Unpin under the pointer, in the state icon's place, and in its menu.
private struct PinnedTab: View {
    let tab: HostStore.Tab
    let page: Page
    @State private var hovering = false
    @Environment(\.look) private var look

    var body: some View {
        let workspace = page.store.workspace(of: tab.id)
        let lit = workspace?.id == page.selectedWorkspaceID && page.selectedTabIDs[workspace?.id ?? ""] == tab.id
        let state = tab.agent?.state == .idle ? nil : tab.agent?.state
        Button {
            if let workspace {
                page.select(workspace, tab: tab.id)
                page.focusKeyboardCard()
            }
        } label: {
            HStack(spacing: 8) {
                IconStack(panes: page.stack(tab))
                Text(page.titleText(tab)).font(.system(size: 13)).lineLimit(1).layoutPriority(1)
                    .foregroundStyle(lit ? look.selected : look.chrome)
                Text(workspace?.label ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, WorkspaceRow.textInset).padding(.trailing, 8 + 18 + 4)
            .frame(height: 28)
        }
        .buttonStyle(ChromeStyle(selected: lit, radius: 10))
        .accessibilityIdentifier("pinned.\(tab.id)")
        .accessibilityLabel("\(page.titleText(tab)), \(workspace?.label ?? "")")
        .accessibilityValue(state?.word ?? "")
        .accessibilityAddTraits(lit ? .isSelected : [])
        .overlay(alignment: .trailing) {
            if hovering {
                IconButton(symbol: "pin.slash", help: "Unpin Tab", size: 18) { page.togglePin(tab) }
                    .padding(.trailing, 5)
                    .accessibilityIdentifier("pinned.\(tab.id).unpin")
            } else if let state {
                StateIcon(state: state).padding(.trailing, 8).allowsHitTesting(false)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { Button("Unpin Tab") { page.togglePin(tab) } }
        .hoverPanel(place: .beside) { close in HoverCard(tabID: tab.id, page: page, close: close) }
    }
}
