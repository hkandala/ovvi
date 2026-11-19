import SwiftUI

/// Over the foot, opened by its agents' box: the machine's agents, or in its place, by the archive button, the
/// archived sessions. The foot's box, its header's × or menu, or Esc close it; in the archived sessions Esc goes back
/// first.
struct AgentsSection: View {
    let pages: WindowPages
    let page: Page
    /// Opened by the user, not restored: the keys come here.
    let focuses: Bool
    let close: () -> Void
    @AppStorage(Page.foldsAndShelves, store: .sidebar) private var opened = ""
    /// The user switched its views: the keys come here too.
    @State private var switched = false
    @FocusState private var focused: Bool
    /// Every lit box (a row, a group's header, the search field, the back row) from the border, on all four sides.
    static let inset: CGFloat = 6
    /// Text and glyphs inside those boxes: the section's columns sit `inset + padding` inside its border.
    static let padding: CGFloat = 6
    /// Its lists' height: five agents under three groups' headers, down to five archived rows in a short window.
    static let listHeight: ClosedRange<CGFloat> = 5 * 48 + 4 * 4 ... 3 * 24 + 5 * 48 + 7 * 4

    var body: some View {
        let archived = opened.hasLine(pages.archivedKey)
        VStack(spacing: 4) {
            header(archived: archived)
            if archived {
                ArchivedShelf(pages: pages, page: page, focuses: focuses || switched, back: back)
            } else {
                AgentsList(pages: pages)
            }
        }
        .padding(Self.inset)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.14))
        }
        // Restored at launch, it leaves the keys to the card.
        .focusable(focuses || switched)
        .focusEffectDisabled()
        .focused($focused)
        .onExitCommand {
            if archived {
                back()
            } else {
                close()
            }
        }
        .onAppear {
            if focuses, !archived {
                // A first responder set during an update is undone.
                DispatchQueue.main.async { focused = true }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agents.section")
    }

    private func show(archived: Bool) {
        switched = true
        withAnimation(.fade) {
            opened = opened.withLine(pages.archivedKey, archived)
        }
        if !archived {
            DispatchQueue.main.async { focused = true }
        }
    }

    private func back() {
        show(archived: false)
    }

    private func header(archived: Bool) -> some View {
        HStack(spacing: 0) {
            if archived {
                Button(action: back) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("Archived · \(pages.machine.name)")
                    }
                    .padding(.horizontal, Self.padding).frame(height: 22)
                }
                .buttonStyle(ChromeStyle(radius: 6))
                .accessibilityLabel("Back to Agents")
                .accessibilityValue("Archived · \(pages.machine.name)")
                .accessibilityIdentifier("agents.back")
            } else {
                Text("Agents · \(pages.machine.name)").padding(.leading, Self.padding)
                    .accessibilityIdentifier("agents.header")
            }
            Spacer(minLength: 8)
            if !archived {
                headerButton("archivebox", ink: 12, "Archived Sessions", id: "agents.archive") { show(archived: true) }
            }
            headerButton("xmark", ink: 10, "Close", id: "agents.close", action: close)
        }
        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        .frame(height: 22)
        .contentShape(.rect)
        .contextMenu {
            Button(archived ? "Show Agents" : "Show Archived Sessions") { show(archived: !archived) }
            Button("Close", action: close)
        }
    }

    /// The glyph's `ink` wide ink `padding` inside its box: the last one's on the section's right column.
    private func headerButton(_ symbol: String, ink: CGFloat, _ help: String, id: String,
                              action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary).frame(width: ink + 2 * Self.padding, height: 22)
        }
        .buttonStyle(ChromeStyle(radius: 6))
        .tip(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(id)
    }
}
