import SwiftUI

/// A folded shelf at the foot of the sidebar (Archived Sessions), as T3 Code's: a quiet header with a chevron at its
/// end, folded at first; open, at most five rows tall, then its rows scroll inside.
struct Shelf<Accessory: View, Content: View>: View {
    let label: String
    let page: Page
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content
    /// The open shelves (`Page.openShelves`), kept across relaunches.
    @AppStorage(Page.openShelves, store: .agents) private var opened = ""
    @State private var under = (top: false, bottom: false)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let open = page.opens(label, in: opened)
        VStack(spacing: 4) {
            header(open: open)
            if open {
                // Lazy, for Archived's pages; as tall as its rows, up to five.
                ScrollView {
                    LazyVStack(spacing: 4) { content() }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 5 * 48 + 4 * 4) // five 48 pt rows, 4 pt apart
                .fixedSize(horizontal: false, vertical: true)
                .onScrollGeometryChange(for: [Bool].self) { geometry in
                    [geometry.contentOffset.y > 0.5,
                     geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 0.5]
                } action: {
                    under = ($1[0], $1[1])
                }
                .fadeEdges(.vertical, start: under.top ? 18 : 0, end: under.bottom ? 18 : 0)
            }
        }
    }

    private func header(open: Bool) -> some View {
        Button {
            withAnimation(reduceMotion && !Animation.forceMotion ? nil : .easeOut(duration: 0.2)) {
                opened = page.toggled(label, in: opened)
            }
        } label: {
            line(open: open) {
                Text(label)
                Spacer(minLength: 0)
                // Room for the accessory, drawn over the row: inside the label it would be part of the header's one
                // accessibility element.
                accessory().hidden().accessibilityHidden(true)
            }
        }
        .buttonStyle(ChromeStyle(radius: 7))
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(open ? "expanded" : "collapsed")
        .accessibilityIdentifier("agents.shelf.\(label)")
        .overlay {
            line(open: open, tail: false) {
                Spacer(minLength: 0)
                accessory()
            }
        }
    }

    /// The header's line: `lead`, then the chevron (only its room without `tail`).
    private func line(open: Bool, tail: Bool = true, @ViewBuilder _ lead: () -> some View) -> some View {
        HStack(spacing: 6) {
            lead()
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(open ? 90 : 0))
                .opacity(tail ? 1 : 0)
                .accessibilityHidden(!tail)
        }
        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 28)
    }
}

extension Page {
    /// The defaults key of the open shelf and the unfolded workspaces, a line each (`shelfKey`).
    /// ponytail: folds are never pruned, so a workspace herdr makes again with a folded-open id starts unfolded.
    static let openShelves = "agentsOpen"

    /// "‹machine› ‹session› ‹label›".
    func shelfKey(_ label: String) -> String {
        "\(store.machine.id) \(id) \(label)"
    }

    /// Whether `opened` (the `openShelves` text) has the line of `label`.
    func opens(_ label: String, in opened: String) -> Bool {
        opened.split(separator: "\n").contains { $0 == shelfKey(label) }
    }

    /// `opened` with the line of `label` added, or taken out when it is there.
    func toggled(_ label: String, in opened: String) -> String {
        let key = shelfKey(label)
        var lines = opened.split(separator: "\n").map(String.init)
        if lines.contains(key) {
            lines.removeAll { $0 == key }
        } else {
            lines.append(key)
        }
        return lines.joined(separator: "\n")
    }
}
