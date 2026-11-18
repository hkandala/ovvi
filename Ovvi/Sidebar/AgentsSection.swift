import SwiftUI

/// Over the foot, opened by its agents' box: the machine's agents, or in its place, by the archive button, the
/// archived sessions. The foot's box or Esc closes it; in the archived sessions Esc goes back first.
struct AgentsSection: View {
    let pages: WindowPages
    let page: Page
    /// Opened by the user, not restored: the keys come here.
    let focuses: Bool
    let close: () -> Void
    @AppStorage(Page.foldsAndShelves, store: .sidebar) private var opened = ""
    /// The user switched its views: the keys come here too.
    @State private var switched = false
    @State private var backLit = false
    @FocusState private var focused: Bool
    private var settings = AppSettings()

    var body: some View {
        let archived = settings.showArchived && opened.hasLine(pages.archivedKey)
        VStack(spacing: 4) {
            header(archived: archived)
            if archived {
                ArchivedShelf(pages: pages, page: page, focuses: focuses || switched, back: back)
            } else {
                AgentsList(pages: pages)
            }
        }
        .padding(.bottom, 4)
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
        (switched, backLit) = (true, false)
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
                // The whole title row goes back; the light is the chevron's and the words'.
                Button(action: back) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("Archived · \(pages.machine.name)")
                    }
                    .padding(.horizontal, 4).frame(height: 22)
                    .background(.primary.opacity(backLit ? 0.05 : 0), in: .rect(cornerRadius: 6))
                    .padding(.leading, WorkspaceRow.textInset - 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onHover { backLit = $0 }
                .accessibilityLabel("Back to Agents")
                .accessibilityValue("Archived · \(pages.machine.name)")
                .accessibilityIdentifier("agents.back")
            } else {
                Text("Agents · \(pages.machine.name)").padding(.leading, WorkspaceRow.textInset)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("agents.header")
            }
            Spacer(minLength: 8)
            if !archived, settings.showArchived {
                Button { show(archived: true) } label: {
                    Image(systemName: "archivebox").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary).frame(width: 20, height: 20)
                }
                .buttonStyle(ChromeStyle(radius: 6))
                .tip("Archived Sessions")
                // Its glyph's ink on the gear's column.
                .padding(.trailing, 4.5)
                .accessibilityLabel("Archived Sessions")
                .accessibilityIdentifier("agents.archive")
            }
        }
        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
        .frame(height: 30)
    }
}
