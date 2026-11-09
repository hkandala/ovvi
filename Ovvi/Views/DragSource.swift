import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The system drag: an AppKit session from the window's content view, which outlives the view that started it
/// (spring-loading shows another tab's page, which drops the dragged card, and a `DragGesture` would be cancelled).
/// It gives the preview and Esc; its end clears the page's drag, whatever view is left.
@MainActor
final class DragSource: NSObject, NSDraggingSource {
    private static let shared = DragSource()
    private weak var page: Page?
    /// The pointer in the dragged view as the drag began: the drag image keeps that distance from the pointer.
    private(set) static var grabbed = CGPoint.zero
    /// The drag's session, from its first move: AppKit can also run a whole session inside `beginDraggingSession`.
    private static var session: NSDraggingSession?

    /// From a `DragGesture`'s change: starts the drag once (the session takes the mouse from there). The preview is
    /// the dragged view's snapshot: `size` from its top left, which is `grabbed` (the pointer in the view) away from
    /// the pointer.
    static func begin(_ item: Dragged, page: Page, grabbed: CGPoint, size: CGSize) {
        // The gesture runs while SwiftUI handles the drag event.
        // Not on a stopped session's last rows and cards: a drop could not write.
        guard page.dragging == nil, page.store.state == .live, let event = NSApp.currentEvent,
              event.type == .leftMouseDragged,
              let view = event.window?.contentView else { return }
        let pasteboard = NSPasteboardItem()
        pasteboard.setString("", forType: NSPasteboard.PasteboardType(UTType.ovviDrag.identifier))
        let dragging = NSDraggingItem(pasteboardWriter: pasteboard)
        let pointer = view.convert(event.locationInWindow, from: nil)
        let rect = NSRect(x: pointer.x - grabbed.x, y: view.isFlipped ? pointer.y - grabbed.y
            : pointer.y + grabbed.y - size.height, width: size.width, height: size.height)
        if case .pane = item, let card = snapshot(view, rect) {
            let lifted = lift(card, from: rect, under: pointer, flipped: view.isFlipped)
            dragging.setDraggingFrame(lifted.frame, contents: lifted.image)
        } else {
            // The capsule's or the row's own shape (its ChromeStyle's), without the window around it.
            var radius: CGFloat = 10, inset: CGFloat = 0
            if case .tab = item {
                (radius, inset) = (TabBar.radius - TabBar.inset, TabBar.inset)
            }
            dragging.setDraggingFrame(rect, contents: snapshot(view, rect).map { image in
                NSImage(size: image.size, flipped: false) { bounds in
                    NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: inset), xRadius: radius, yRadius: radius)
                        .addClip()
                    image.draw(in: bounds)
                    return true
                }
            })
        }
        shared.page = page
        self.grabbed = grabbed
        page.dragging = item
        view.beginDraggingSession(with: [dragging], event: event, source: shared)
    }

    /// For a drop that shows its own landing. SwiftUI's drop target sets `animatesToDestination` on every drop and
    /// names no place, so AppKit keeps the image where it was let go for about 0.35 s before the session ends: over
    /// the view gliding into its place. An empty image takes it away at once.
    static func dropImage() {
        let empty: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void = { item, _, _ in
            item.imageComponentsProvider = { [] }
        }
        session?.enumerateDraggingItems(options: [], for: nil, classes: [NSPasteboardItem.self], searchOptions: [:],
                                        using: empty)
    }

    private static func snapshot(_ view: NSView, _ rect: NSRect) -> NSImage? {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: bitmap)
        let image = NSImage(size: rect.size)
        image.addRepresentation(bitmap)
        return image
    }

    /// A dragged card as a lifted card: one small card shape, 240 × 150 pt, filled with the card's top
    /// (header and terminal) scaled to cover it, its corners rounded, at 0.85 with a soft shadow; the pointer sits
    /// over the header where it grabbed it. The terminal's Metal layer may not draw into the snapshot: the card's
    /// fill shows there then.
    private static func lift(_ card: NSImage, from rect: NSRect, under point: NSPoint,
                             flipped: Bool) -> (frame: NSRect, image: NSImage)
    {
        let size = NSSize(width: 240, height: 150), margin: CGFloat = 20
        let scale = max(size.width / rect.width, size.height / rect.height)
        // The grab point from the lifted card's top left, in its scaled points.
        let grab = NSPoint(x: min((point.x - rect.minX) * scale, size.width - 8),
                           y: min((flipped ? point.y - rect.minY : rect.maxY - point.y) * scale, size.height - 8))
        let frame = NSRect(x: point.x - grab.x - margin,
                           y: (flipped ? point.y - grab.y : point.y - (size.height - grab.y)) - margin,
                           width: size.width + 2 * margin, height: size.height + 2 * margin)
        let image = NSImage(size: frame.size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let inside = NSRect(origin: NSPoint(x: margin, y: margin), size: size)
            context.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: CGColor(gray: 0, alpha: 0.35))
            context.setAlpha(0.85)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            NSBezierPath(roundedRect: inside, xRadius: 10, yRadius: 10).addClip()
            // Top aligned: the header always shows.
            card.draw(in: NSRect(x: margin, y: margin + size.height - rect.height * scale,
                                 width: rect.width * scale, height: rect.height * scale))
            context.endTransparencyLayer()
            return true
        }
        return (frame, image)
    }

    nonisolated func draggingSession(_: NSDraggingSession,
                                     sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation
    {
        context == .withinApplication ? .move : []
    }

    /// The session shows its image some frames after it began, first where the view is, and follows the pointer only
    /// from its first move: the view dims then, so it never shows dimmed with no image over it.
    func draggingSession(_ session: NSDraggingSession, movedTo _: NSPoint) {
        Self.session = session
        if let page, page.lifted == nil {
            page.lifted = page.dragging
        }
    }

    nonisolated func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
        MainActor.assumeIsolated {
            Self.session = nil
            page?.dragging = nil
            page?.lifted = nil
            page = nil
        }
    }
}
