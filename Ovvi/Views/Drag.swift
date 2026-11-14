import AppKit
import HerdrKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ovviDrag = UTType(exportedAs: "dev.ovvi.app.drag")
}

/// Nothing once the drag ends: an update can come late.
func springTask(_ page: Page, _ select: @escaping () -> Void) -> Task<Void, Never> {
    Task {
        if await (try? Task.sleep(for: .milliseconds(650))) != nil, page.dragging != nil {
            select()
        }
    }
}

enum DropTarget {
    case card(String, edge: Heading?)
    case tab(String)
    case move(Destination)
}

struct DropIndicator: View {
    var radius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(Color.accentColor.opacity(0.2)).overlay(shape.strokeBorder(Color.accentColor, lineWidth: 2))
            .allowsHitTesting(false)
            .accessibilityElement().accessibilityLabel("Drop target").accessibilityIdentifier("drop.indicator")
    }
}

/// A row-sized drop target in the sidebar (New Space, Pin Space): lit as a drop indicator while the drop would land
/// there, else outlined as a row.
struct DropRow: View {
    let title: String
    let lit: Bool

    var body: some View {
        Text(title).foregroundStyle(.secondary).padding(.leading, WorkspaceRow.textInset)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background {
                if lit {
                    DropIndicator()
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
    }
}

func dropEdge(_ point: CGPoint, in size: CGSize) -> Heading? {
    let across = point.x / max(size.width, 1), down = point.y / max(size.height, 1)
    let distances: [(Heading, Double)] = [(.left, across), (.right, 1 - across), (.up, down), (.down, 1 - down)]
    guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 < 0.25 else { return nil }
    return nearest.0
}

struct CardDrop: DropDelegate {
    let paneID: String
    let page: Page
    let size: CGSize
    @Binding var zone: Heading??

    func validateDrop(info _: DropInfo) -> Bool {
        page.dragging?.paneID != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let target = target(info.location)
        if zone != target {
            withAnimation(.highlight) { zone = target }
        }
        return DropProposal(operation: target == nil ? .forbidden : .move)
    }

    func dropExited(info _: DropInfo) {
        withAnimation(.highlight) { zone = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        zone = nil
        guard let dragged = page.dragging?.paneID, let edge = target(info.location) else { return false }
        Task { await page.drop(dragged, on: .card(paneID, edge: edge)) }
        return true
    }

    private func target(_ point: CGPoint) -> Heading?? {
        guard let dragged = page.dragging?.paneID, dragged != paneID,
              let source = page.store.pane(dragged), let pane = page.store.pane(paneID) else { return nil }
        let edge = dropEdge(point, in: size)
        return edge == nil && source.tabID != pane.tabID ? nil : .some(edge)
    }
}

struct PaneDrop: DropDelegate {
    let page: Page
    let target: DropTarget
    @Binding var over: Bool
    var enabled = true

    func validateDrop(info _: DropInfo) -> Bool {
        takes
    }

    func dropEntered(info _: DropInfo) {
        if takes {
            withAnimation(.highlight) { over = true }
        }
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        withAnimation(.highlight) { over = false }
    }

    func performDrop(info _: DropInfo) -> Bool {
        over = false
        guard takes else { return false }
        switch (page.dragging, target) {
        case let (.pane(id), _):
            Task { await page.drop(id, on: target) }
        case let (.tab(id), .move(.newTab(workspaceID, _))):
            Task { await page.drop(tab: id, on: workspaceID) }
        case let (.tab(id), .move(.newWorkspace)):
            Task { await page.drop(tab: id, on: nil) }
        default:
            return false
        }
        return true
    }

    private var takes: Bool {
        guard enabled else { return false }
        return switch (page.dragging, target) {
        case (.pane, _): true
        case let (.tab(id), .move(.newTab(workspaceID, _))): page.store.workspace(of: id)?.id != workspaceID
        case (.tab, .move(.newWorkspace)): true
        default: false
        }
    }
}

/// Any drag here is a pane's or a tab's: workspace rows are in the sidebar, which is closed while the button shows.
struct SpringDrop: DropDelegate {
    let page: Page
    @Binding var over: Bool
    @Binding var spring: Task<Void, Never>?
    let open: () -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        page.dragging != nil
    }

    func dropEntered(info _: DropInfo) {
        withAnimation(.highlight) { over = true }
        spring?.cancel()
        spring = springTask(page, open)
    }

    func dropExited(info _: DropInfo) {
        spring?.cancel()
        withAnimation(.highlight) { over = false }
    }

    func performDrop(info: DropInfo) -> Bool {
        dropExited(info: info)
        return false
    }
}

extension Animation {
    static var highlight: Animation? {
        .motion(.easeOut(duration: 0.12))
    }

    static var slide: Animation? {
        reduced ? nil : .timingCurve(.slide, duration: 0.22)
    }

    static var fade: Animation? {
        reduced ? nil : .easeOut(duration: 0.2)
    }
}

extension UnitCurve {
    /// Rex's "production" curve.
    static let slide = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.9),
                                        endControlPoint: UnitPoint(x: 0.3, y: 1))
}

struct Landing: Equatable {
    let ids: [String]
    let offset: CGFloat
    let count: Int
}

extension View {
    /// No hover meanwhile: a view passing under the still pointer takes the hover and keeps it (no hover event
    /// follows).
    func lands(_ id: String, _ landing: Landing?) -> some View {
        modifier(Lands(landing: landing?.ids.contains(id) == true ? landing : nil))
    }

    /// After a drop, a `dropUpdated` can come after `performDrop` with no `dropExited` to follow, even once the session
    /// ends.
    func clearsDrop(_ page: Page, _ clear: @escaping () -> Void) -> some View {
        onChange(of: page.dragging == nil) { clear() }
    }

    func dragSource(_ item: Dragged, page: Page, previewSize: CGSize? = nil) -> some View {
        modifier(DragSourceModifier(item: item, page: page, previewSize: previewSize))
    }
}

private struct DragSourceModifier: ViewModifier {
    let item: Dragged
    let page: Page
    let previewSize: CGSize?
    /// Its size, not its frame in the window: the frame changes as its row scrolls, an update of every tab capsule at
    /// each layout.
    @State private var size = CGSize.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
                // Where the mouse went down: a busy app's first change comes late.
                DragSource.begin(item, page: page, grabbed: value.startLocation, moved: value.translation,
                                 size: previewSize ?? size)
            })
    }
}

private struct Lands: ViewModifier {
    let landing: Landing?

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0, trigger: Animation.reduced ? nil : landing) { content, offset in
            content.offset(x: offset)
                .allowsHitTesting(offset == 0)
        } keyframes: { _ in
            MoveKeyframe(landing?.offset ?? 0)
            LinearKeyframe(0, duration: 0.22, timingCurve: .slide)
        }
    }
}
