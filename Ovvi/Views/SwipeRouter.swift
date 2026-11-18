import SwiftUI

enum SwipeRouter {
    static func install() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { route(event) } ? nil : event
        }
    }

    private enum Step {
        case session(Int), row(Int)
    }

    private static func take(_ step: Step, _ event: NSEvent) {
        guard let pages = WindowPages.windows.first(where: { $0.window === event.window }), !pages.panelOpen
        else { return }
        switch step {
        case let .session(offset): pages.step(offset)
        case let .row(offset): pages.current?.stepWorkspace(offset)
        }
    }

    fileprivate static let anchors = NSHashTable<PagesAnchor.Anchor>.weakObjects()
    fileprivate static let strips = NSHashTable<NSView>.weakObjects()
    private weak static var pager: PagesAnchor.Anchor?
    private static var lifted = false
    private static var picked = false
    private static var option = false
    private static var moved = 0.0, sideways = 0.0
    private static var speed = 0.0, last = 0.0, wheeled = 0.0

    private static func route(_ event: NSEvent) -> Bool {
        let deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
        if event.phase.isEmpty, event.momentumPhase.isEmpty {
            return wheel(event)
        }
        if event.phase == .mayBegin || event.phase == .began {
            option = event.modifierFlags.contains(.option)
            // The next touch may end with no move (`.cancelled`): not the last swipe's.
            pager = nil
        }
        if event.phase == .began {
            (picked, lifted, moved, sideways, speed) = (false, false, 0, 0, 0)
        }
        // A scroll moves the content against the fingers' delta; half the last speed smooths a jittery step.
        if event.phase == .changed, event.timestamp > last {
            speed = speed / 2 - deltaX / (event.timestamp - last) / 2
        }
        // Fingers that stopped ahead of the lift. Not 50 ms: CI's VM posts a quick flick's moves about 50 ms apart.
        if event.phase == .ended, event.timestamp - last > 0.1 {
            speed = 0
        }
        last = event.timestamp
        if let pager {
            give(event, to: pager)
            return true
        }
        if !picked {
            moved += abs(deltaX) + abs(deltaY)
            sideways -= deltaX
            if moved >= 4 {
                picked = true
                pick(event)
            }
        }
        return pager != nil || option
    }

    private static func pick(_ event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            pager = anchors.allObjects.first { anchor in
                anchor.contains(event) || option && anchor.marks.drag != nil && anchor.marks.area.width > 0
                    && anchor.window === event.window
            }
            if pager == nil, option {
                take(.session(sideways > 0 ? 1 : -1), event)
            }
            pager?.marks.drag?(sideways, true)
        } else if option {
            take(.row(up(event) > 0 ? -1 : 1), event)
        }
    }

    /// The vertical delta toward the top of the pad (or a wheel turned away), whatever the scroll direction.
    private static func up(_ event: NSEvent) -> CGFloat {
        event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
    }

    private static func give(_ event: NSEvent, to pager: PagesAnchor.Anchor) {
        if event.phase == .changed {
            pager.marks.drag?(-event.scrollingDeltaX, false)
        } else if event.phase == .ended || event.phase == .cancelled, !lifted {
            lifted = true
            // A gesture the system took (Mission Control) turns no page.
            pager.marks.lift?(event.phase == .cancelled ? 0 : speed)
        }
    }

    private static func wheel(_ event: NSEvent) -> Bool {
        let deltaX = event.scrollingDeltaX, deltaY = event.scrollingDeltaY
        if event.modifierFlags.contains(.option) {
            let across = abs(deltaX) > abs(deltaY)
            turn({ take(across ? .session($0) : .row($0), event) }, across ? deltaX : up(event), at: event.timestamp)
            return true
        }
        // A mouse's wheel turns only up and down: over the tab strip, it scrolls the strip sideways. Not under a
        // panel or the overview, which leaves the strip in the window, unseen.
        if abs(deltaY) > abs(deltaX),
           let pages = WindowPages.windows.first(where: { $0.window === event.window }), !pages.panelOpen,
           !pages.overview,
           let strip = strips.allObjects.lazy.compactMap(\.enclosingScrollView).first(where: {
               $0.window === event.window && $0.bounds.contains($0.convert(event.locationInWindow, from: nil))
           })
        {
            let step = event.hasPreciseScrollingDeltas ? deltaY : deltaY * strip.horizontalLineScroll
            // `scroll(_:)` keeps the clip inside the tabs.
            strip.documentView?.scroll(NSPoint(
                x: strip.contentView.bounds.minX - step,
                y: strip.contentView.bounds.minY,
            ))
            return true
        }
        guard abs(deltaX) > abs(deltaY),
              let pages = anchors.allObjects.first(where: { $0.contains(event) }) else { return false }
        turn(pages.marks.step, deltaX, at: event.timestamp)
        return true
    }

    /// A wheel event within 0.3 s of the one before, by the events' own times, is the same wheel: a page shown by the
    /// first can hold the main thread past 0.3 s before the next is handled.
    private static func turn(_ step: ((Int) -> Void)?, _ delta: CGFloat, at time: TimeInterval) {
        if delta != 0, time - wheeled > 0.3 {
            step?(delta > 0 ? -1 : 1)
        }
        wheeled = time
    }
}

struct PagesAnchor: NSViewRepresentable {
    var step: ((Int) -> Void)?
    var drag: ((Double, Bool) -> Void)?
    var lift: ((Double) -> Void)?
    var area = CGRect.zero

    func makeNSView(context _: Context) -> Anchor {
        let view = Anchor()
        view.marks = self
        return view
    }

    func updateNSView(_ view: Anchor, context _: Context) {
        view.marks = self
    }

    /// No size: over the sidebar's rows, a view the size of the pages takes accessibility's hit tests, and XCUITest
    /// finds no hit point for a row.
    func sizeThatFits(_: ProposedViewSize, nsView _: Anchor, context _: Context) -> CGSize? {
        .zero
    }

    final class Anchor: NSView {
        var marks = PagesAnchor()

        /// The window's content view is its whole SwiftUI host, the window's full size; its points count from the
        /// bottom.
        func contains(_ event: NSEvent) -> Bool {
            guard marks.drag != nil, let window, event.window === window,
                  let height = window.contentView?.bounds.height else { return false }
            let point = event.locationInWindow
            let area = marks.area
            return point.x >= area.minX && point.x < area.maxX && height - point.y >= area.minY
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                SwipeRouter.anchors.add(self)
            }
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }
}

/// In the tab strip's scroll content: its scroll view is the strip's.
struct StripAnchor: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        SwipeRouter.strips.add(view)
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    /// No size, as `PagesAnchor`.
    func sizeThatFits(_: ProposedViewSize, nsView _: NSView, context _: Context) -> CGSize? {
        .zero
    }
}

/// `slide` is observed only by `Pager`, so a swipe's moves redraw nothing else; `moving` by the sidebar, which lays out
/// the other pages only then.
@Observable
final class Swipe {
    var slide = 0.0
    @ObservationIgnored var drawn = 0.0
    var moving = false
    @ObservationIgnored var moves = 0

    static func landing(_ page: Double, speed: Double, count: Int) -> Int {
        let near = abs(speed) < 100 ? page.rounded() : speed > 0 ? page.rounded(.up) : page.rounded(.down)
        return min(max(Int(near), 0), count - 1)
    }
}

struct Pager<Content: View>: View {
    let swipe: Swipe
    let width: Double
    @ViewBuilder let content: Content

    var body: some View {
        content.modifier(Slid(offset: swipe.moving ? swipe.slide * width : 0, swipe: swipe))
            .frame(width: width, alignment: .leading)
            .frame(maxHeight: .infinity)
            .clipped()
    }
}

private struct Slid: ViewModifier, Animatable {
    var offset: Double
    let swipe: Swipe
    var animatableData: Double {
        get { offset }
        set { offset = newValue }
    }

    func body(content: Content) -> some View {
        if swipe.moving {
            swipe.drawn = offset
            Latency.shared.slid(offset)
        }
        return content.offset(x: -offset)
    }
}

extension Animation {
    /// 0.2 s with no bounce: 0.14 s feels too quick.
    static func session(speed: Double = 0, distance: Double = 0) -> Animation? {
        // Critically damped, it would go past the page from a relative speed over ω = 2π / response.
        let response = 0.2, initial = distance == 0 ? 0 : min(max(speed / distance, 0), 2 * .pi / response)
        let spring = Animation.motion(.interpolatingSpring(duration: response, bounce: 0, initialVelocity: initial))
        return spring.map { Animation(Arrive(spring: $0)) }
    }
}

/// Logically complete once within half a point of its end: its own logical end, at its 0.2 s, leaves a slow lift's
/// pages up to 3 pt short, held there by the session's show (100 ms of main thread), and then they jump.
private struct Arrive: CustomAnimation {
    let spring: Animation

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let now = spring.animate(value: value, time: time, context: &context)
        var left = value
        left -= now ?? value
        context.isLogicallyComplete = left.magnitudeSquared < 0.25
        return now
    }

    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        spring.velocity(value: value, time: time, context: context)
    }

    func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval,
                                          context: inout AnimationContext<V>) -> Bool
    {
        spring.shouldMerge(previous: previous, value: value, time: time, context: &context)
    }
}
