import GhosttyTerminal
import HerdrKit
import SwiftUI

struct FindBar: View {
    let find: Find
    let page: Page
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("Find", text: Bindable(find).query)
                .textFieldStyle(.plain)
                .focused($focused)
                .focusSoon($focused)
                .onSubmit { Task { await find.step(1) } }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    Task { await find.step(-1) }
                    return .handled
                }
                .onExitCommand { page.closeFind() }
                .accessibilityIdentifier("find.field")
            Text(find.count)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
                .accessibilityIdentifier("find.count")
            IconButton(symbol: "chevron.up", help: "Find Previous", size: 22) { Task { await find.step(-1) } }
                .accessibilityIdentifier("find.previous")
            IconButton(symbol: "chevron.down", help: "Find Next", key: .hotkey("edit.find-next"), size: 22) {
                Task { await find.step(1) }
            }
            .accessibilityIdentifier("find.next")
            IconButton(symbol: "xmark", help: "Close", size: 22) { page.closeFind() }
                .accessibilityIdentifier("find.close")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(width: 320, height: 32)
        .floatingGlass(in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("find")
        .onChange(of: page.findFocus) { focused = true }
    }
}

/// Placed by the surface's cell size: the terminal has no padding.
struct FindHighlights: View {
    let find: Find
    let terminal: PaneTerminal
    @Environment(\.displayScale) private var scale

    var body: some View {
        let metrics = terminal.view.metrics
        let cell = CGSize(width: CGFloat(metrics?.cellWidthPixels ?? 0) / scale,
                          height: CGFloat(metrics?.cellHeightPixels ?? 0) / scale)
        ZStack(alignment: .topLeading) {
            ForEach(Array(find.shown.enumerated()), id: \.offset) { index, hit in
                Rectangle()
                    .fill(Color.accentColor.opacity(index == find.shownCurrent ? 0.45 : 0.2))
                    .frame(width: cell.width * CGFloat(hit.length), height: cell.height)
                    .offset(x: cell.width * CGFloat(hit.column), y: cell.height * CGFloat(hit.row))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .readableText(
            "\(find.shown.count) shown, current row \(find.shownCurrent.map { "\(find.shown[$0].row)" } ?? "none")",
        )
        .accessibilityLabel("Matches")
        .accessibilityIdentifier("find.highlights")
        .onAppear { [weak find] in terminal.onFrame = { find?.screenChanged() } }
        .onDisappear { terminal.onFrame = nil }
    }
}

extension Page {
    func openFind(_ target: HostStore.Pane?) {
        guard let pane = target ?? keyboardPane else { return }
        if find?.paneID != pane.id {
            dropFind()
            let find = Find(paneID: pane.id, store: store)
            self.find = find
            Task { await find.read() }
        }
        findFocus += 1
    }

    func closeFind() {
        guard let paneID = find?.paneID else { return }
        dropFind()
        if let pane = store.pane(paneID), pane.tabID == selectedTab?.id || floats(pane) {
            go(to: pane)
        }
    }

    var findHidden: Bool {
        guard let find, store.pane(find.paneID).map(floats) != true else { return false }
        let tabID = store.pane(find.paneID)?.tabID
        return tabID != selectedTab?.id || tabID.flatMap { zoomedPanes[$0] }.map { $0 != find.paneID } == true
    }

    func dropFind() {
        find?.close()
        find = nil
    }
}
