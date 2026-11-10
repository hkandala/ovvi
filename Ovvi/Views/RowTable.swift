import AppKit
import SwiftUI

/// Drawn by AppKit in a table that reuses the few row views in view: as SwiftUI views each typed key makes the rows in
/// view anew, and with an accessibility client (Raycast, VoiceOver) each new row makes SwiftUI walk every focusable
/// view of the window; each keycap's live glass is a SwiftUI host of its own.
struct RowTable: NSViewRepresentable {
    let name: String
    let items: [FilterList.Item]
    let lit: Int
    let reveal: Int?
    let rowHeight: CGFloat
    let inset: CGFloat
    let act: (FilterList.Item) -> Void
    let hover: (FilterList.Item) -> Void

    static let spacing: CGFloat = 2
    static let headerHeight = NSHostingView(rootView: Text(verbatim: "Tabs").font(.system(size: 11, weight: .medium)))
        .fittingSize.height

    static func height(_ items: [FilterList.Item], rowHeight: CGFloat, inset: CGFloat) -> CGFloat {
        items.indices.reduce(0) { $0 + span(items, $1, rowHeight, inset) }
    }

    /// A table puts half its row spacing above the first row, and scrolls short of a scroll view's inset.
    static func span(_ items: [FilterList.Item], _ row: Int, _ height: CGFloat, _ inset: CGFloat) -> CGFloat {
        let gap = row < items.count - 1 ? spacing : inset
        return height + gap + (header(items, row) == nil ? 0 : headerHeight + (row > 0 ? 6 : 0) + spacing)
    }

    static func header(_ items: [FilterList.Item], _ row: Int) -> String? {
        let section = items[row].section
        return section == (row > 0 ? items[row - 1].section : nil) || section?.isEmpty != false ? nil : section
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = Table()
        let column = NSTableColumn()
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.intercellSpacing = .zero
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let table = scroll.documentView as? NSTableView else { return }
        // Rows as tall as the ones shown keep their views and show the new rows. A reload makes them anew, and an
        // element a test or VoiceOver holds goes with them.
        let spans = items.indices.map { Self.span(items, $0, rowHeight, inset) }
        let reloads = spans != coordinator.spans
        if reloads {
            coordinator.spans = spans
            table.reloadData()
        } else {
            table.enumerateAvailableRowViews { rowView, row in
                (rowView.view(atColumn: 0) as? RowView)?.show(self, row)
            }
        }
        guard let reveal, items.indices.contains(reveal), reloads || reveal != coordinator.revealed else { return }
        coordinator.revealed = reveal
        if scroll.contentView.bounds.height > 0 {
            table.scrollRowToVisible(reveal)
        } else {
            DispatchQueue.main.async { table.scrollRowToVisible(reveal) }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private final class Table: NSTableView {
        override var acceptsFirstResponder: Bool {
            false
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: RowTable
        var spans: [CGFloat] = []
        var revealed: Int?

        init(parent: RowTable) {
            self.parent = parent
        }

        func numberOfRows(in _: NSTableView) -> Int {
            parent.items.count
        }

        func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
            spans.indices.contains(row) ? spans[row] : RowTable.span(parent.items, row, parent.rowHeight, parent.inset)
        }

        func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
            let view = tableView.makeView(withIdentifier: RowView.id, owner: nil) as? RowView ?? RowView()
            view.show(parent, row)
            return view
        }

        func tableView(_: NSTableView, didRemove rowView: NSTableRowView, forRow _: Int) {
            (rowView.view(atColumn: 0) as? RowView)?.removed()
        }

        func tableView(_: NSTableView, shouldSelectRow _: Int) -> Bool {
            false
        }
    }
}
