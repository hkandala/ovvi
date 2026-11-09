import AppKit
import HerdrKit
import SwiftUI
import UniformTypeIdentifiers

/// What a drag in a window carries. The page holds it; the pasteboard only routes the drag to the
/// app's drop targets.
enum Dragged: Equatable {
    case pane(String)
    case tab(String)
    case workspace(String)

    var paneID: String? {
        if case let .pane(id) = self {
            id
        } else {
            nil
        }
    }
}

extension UTType {
    static let ovviDrag = UTType(exportedAs: "dev.ovvi.app.drag")
}

/// Holding a dragged pane over a tab's capsule or a workspace's row 0.65 s selects it (Rex's spring-loading), and a
/// pane or a tab over the workspace button opens its menu; not after the drag ended (a late update).
func springTask(_ page: Page, _ select: @escaping () -> Void) -> Task<Void, Never> {
    Task {
        if await (try? Task.sleep(for: .milliseconds(650))) != nil, page.dragging != nil {
            select()
        }
    }
}

enum DropTarget {
    /// A card: its center (nil) or an edge.
    case card(String, edge: Heading?)
    case tab(String)
    /// A new tab or a new workspace.
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

/// A card's drop zones: the outer quarter on each side is that edge (the nearest one in a corner), the rest is
/// the center (nil).
func dropEdge(_ point: CGPoint, in size: CGSize) -> Heading? {
    let across = point.x / max(size.width, 1), down = point.y / max(size.height, 1)
    let distances: [(Heading, Double)] = [(.left, across), (.right, 1 - across), (.up, down), (.down, 1 - down)]
    guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 < 0.25 else { return nil }
    return nearest.0
}

/// A pane dragged over a card: the center of another card in its tab swaps, an edge of any other card places it
/// beside; its own card and another tab's center are not targets.
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

    /// The edge or the center (`.some(nil)`), nil when not a target.
    private func target(_ point: CGPoint) -> Heading?? {
        guard let dragged = page.dragging?.paneID, dragged != paneID,
              let source = page.store.pane(dragged), let pane = page.store.pane(paneID) else { return nil }
        let edge = dropEdge(point, in: size)
        return edge == nil && source.tabID != pane.tabID ? nil : .some(edge)
    }
}

/// A pane dragged over a place with one target (the `+`, the tab track's end, a sidebar's empty space, a workspace
/// menu row), or a tab over a new tab in another workspace (a workspace menu row) or a new workspace.
struct PaneDrop: DropDelegate {
    let page: Page
    let target: DropTarget
    @Binding var over: Bool
    /// Off: a hidden workspace menu's row.
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

/// A drag held over the collapsed sidebar's workspace button opens the workspace menu after 0.65 s, so the drop
/// can go on a row there; a drop on the button itself is none. Any drag here is a pane's or a tab's: workspace
/// rows are in the sidebar, which is closed while the button shows.
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
    /// A drop target's highlight.
    static let highlight = Animation.easeOut(duration: 0.12)

    /// Rex's insertion timing: 0.22 s on its "production" curve. Tabs and rows slide apart with it; none with
    /// Reduce Motion (from AppKit: a drop delegate has no environment).
    static var slide: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .timingCurve(.slide, duration: 0.22)
    }
}

extension UnitCurve {
    /// Rex's "production" curve.
    static let slide = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.9),
                                        endControlPoint: UnitPoint(x: 0.3, y: 1))
}

/// The views dropped last (a tab, or a workspace's rows), and how far from their place the drag image left them: they
/// glide in from there.
struct Landing: Equatable {
    let ids: [String]
    let offset: CGFloat
    /// A new drop at the same offset glides too.
    let count: Int
}

extension View {
    /// Glides in from `landing`'s offset when it names `id`, over 0.22 s on the slide's curve. No hover meanwhile:
    /// passing under the still pointer, a tab took the × and kept it once there (no hover event came after).
    func lands(_ id: String, _ landing: Landing?, axis: Axis) -> some View {
        modifier(Lands(landing: landing?.ids.contains(id) == true ? landing : nil, axis: axis))
    }

    /// Clears a target's drop state when a drag starts or ends: after a drop, a `dropUpdated` can come after
    /// `performDrop` with no `dropExited` to follow (seen by hand: the highlight stayed), even after the session
    /// ended.
    func clearsDrop(_ page: Page, _ clear: @escaping () -> Void) -> some View {
        onChange(of: page.dragging == nil) { clear() }
    }

    /// Starts a drag of `item` after 4 pt; the view's frame is the preview, or `previewSize` from its top left.
    func dragSource(_ item: Dragged, page: Page, previewSize: CGSize? = nil) -> some View {
        modifier(DragSourceModifier(item: item, page: page, previewSize: previewSize))
    }
}

private struct DragSourceModifier: ViewModifier {
    let item: Dragged
    let page: Page
    let previewSize: CGSize?
    /// Its size, not its frame in the window: that one changes as its row scrolls, and every tab capsule wrote it to
    /// its state at each layout (a second update of each capsule a workspace switch made).
    @State private var size = CGSize.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
                // Where the mouse went down: a busy app's first change comes late, and the image then sat off the
                // pointer's grab, and a row's drop above or below where it was let go.
                DragSource.begin(item, page: page, grabbed: value.startLocation, size: previewSize ?? size)
            })
    }
}

private struct Lands: ViewModifier {
    let landing: Landing?
    let axis: Axis

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0, trigger: landing) { content, offset in
            content.offset(x: axis == .horizontal ? offset : 0, y: axis == .vertical ? offset : 0)
                .allowsHitTesting(offset == 0)
        } keyframes: { _ in
            MoveKeyframe(landing?.offset ?? 0)
            LinearKeyframe(0, duration: 0.22, timingCurve: .slide)
        }
    }
}
