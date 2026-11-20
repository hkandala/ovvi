import SwiftUI

/// Moved and sized by Core Animation: the motion runs in the render server, so a busy main thread (herdr's answer, a
/// new terminal, a web page, other apps) drops none of its frames.
struct CardMotion<Content: View>: NSViewRepresentable {
    let rect: CGRect
    let move: Int
    /// A new card's place outside the page, from which it slides in with the others.
    let start: CGRect?
    let hidden: Bool
    let id: String
    let look: Look
    let content: Content

    func makeNSView(context _: Context) -> MovingCard {
        let card = MovingCard(move: move, rect: start ?? rect)
        card.id = id
        card.host.rootView = AnyView(content.environment(\.chromeLink, card.link))
        if SettlingHost.record {
            card.setAccessibilityElement(true)
            card.setAccessibilityRole(.group)
        }
        if start != nil {
            card.arm(move, to: rect, fade: true)
        }
        return card
    }

    /// Its frame's size. Without it, SwiftUI asks Auto Layout for the fitting size of the card's whole view tree at
    /// every layout, each frame of a slide.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView _: MovingCard, context _: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    func updateNSView(_ card: MovingCard, context _: Context) {
        card.host.rootView = AnyView(content.environment(\.chromeLink, card.link))
        card.look = look
        card.id = id
        card.hide(hidden)
        if SettlingHost.record {
            card.setAccessibilityIdentifier("motion.\(id)")
        }
        // No motion (0) lands at once, also the first change after the motions went off.
        if move != card.move, move != 0 {
            card.arm(move, to: rect, fade: false)
        } else {
            card.rect = rect
        }
    }
}

final class MovingCard: NSView {
    /// Every card's motion: ease-out, no overshoot; 0.2 s reads slow.
    static let slide = 0.13
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    var id = ""
    private let chrome = CardChrome()
    private(set) lazy var link = ChromeLink(self)
    private(set) var move: Int
    var rect: CGRect
    var look = Look(style: .glass, dark: true) {
        didSet {
            if look != oldValue {
                chrome.paint(look, keyboard: lit.keyboard, active: lit.active)
            }
        }
    }

    /// The keyboard's card, and `active` when its page shows more than it.
    var lit = (keyboard: false, active: false) {
        didSet {
            if lit != oldValue {
                chrome.paint(look, keyboard: lit.keyboard, active: lit.active)
            }
        }
    }

    private var motions = 0
    private var slides = 0

    init(move: Int, rect: CGRect) {
        (self.move, self.rect) = (move, rect)
        super.init(frame: .zero)
        wantsLayer = true
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.layer?.cornerRadius = CardSurface.radius
        host.layer?.cornerCurve = .continuous
        addSubview(chrome)
        addSubview(host)
        Self.all.add(self)
        chrome.paint(look, keyboard: lit.keyboard, active: lit.active)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    var moving: Bool {
        layer?.animation(forKey: "motion.position") != nil
    }

    override var isFlipped: Bool {
        true
    }

    /// One motion to the card's final place, which SwiftUI sets ahead of this call or after it. The content lays out
    /// once, at its final size, and shows only within the moving card.
    func arm(_ move: Int, to rect: CGRect, fade: Bool) {
        let old = self.rect
        (self.move, self.rect) = (move, rect)
        host.frame.size = rect.size
        // The same place (herdr's answer to a split shown ahead, its ratios as 32-bit floats): a motion again would
        // start its curve over.
        let same = zip([old.minX, old.minY, old.maxX, old.maxY], [rect.minX, rect.minY, rect.maxX, rect.maxY])
            .allSatisfy { abs($0 - $1) < 0.5 }
        guard let layer, old.width > 0, !same else { return }
        // The superlayer's y grows upward.
        var size = old.size, offset = CGPoint(x: old.minX - rect.minX, y: rect.maxY - old.maxY)
        if let shown = layer.presentation(), moving {
            size = shown.bounds.size
            offset.x += shown.position.x - layer.position.x
            offset.y += shown.position.y - layer.position.y
        }
        guard size != rect.size || offset != .zero else { return }
        let position = animation("position", NSValue(point: offset), NSValue(point: .zero))
        position.isAdditive = true
        var animations = [animation("bounds.size", NSValue(size: size), NSValue(size: rect.size)), position]
        if fade {
            animations.append(animation("opacity", 0, 1, duration: MovingCard.slide / 2))
        }
        motions += 1
        let motion = motions
        CATransaction.begin()
        // The card's motion and its surface's in one commit, as in setFrameSize.
        CATransaction.lock()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, motion == motions else { return }
            host.layer?.masksToBounds = false
            host.layer?.removeAnimation(forKey: "motion")
        }
        for animation in animations {
            layer.add(animation, forKey: "motion.\(animation.keyPath ?? "")")
        }
        chrome.frame = CGRect(origin: .zero, size: rect.size)
        chrome.place(rect.size)
        chrome.animate(from: size, to: rect.size) { self.animation($0, $1, $2) }
        clip(from: size, to: rect.size)
        CATransaction.commit()
        CATransaction.unlock()
        if SettlingHost.record {
            slides += 1
            setAccessibilityLabel("slides \(slides)")
            let edges = [-offset.x, offset.y - rect.height + size.height, -offset.x + rect.width - size.width, offset.y]
            motionTrack.change(slides, in: window, content: host.frame.size, edges: edges)
        }
    }

    /// Only the content is cut, to the card's size at each frame.
    private func clip(from old: CGSize, to new: CGSize) {
        guard let content = host.layer else { return }
        content.masksToBounds = true
        let clip = animation("bounds.size", NSValue(size: old), NSValue(size: new))
        (clip.fillMode, clip.isRemovedOnCompletion) = (.forwards, false)
        content.add(clip, forKey: "motion")
    }

    private lazy var motionTrack = MotionTrack(card: layer ?? CALayer(), surface: chrome.surface) { [weak self] in
        self?.setAccessibilityLabel($0)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if SettlingHost.record {
            motionTrack.moved(to: window)
        }
    }

    override func setFrameOrigin(_ origin: NSPoint) {
        if SettlingHost.record, origin != frame.origin {
            motionTrack.change(slides, in: window, content: host.frame.size)
        }
        super.setFrameOrigin(origin)
    }

    override func setFrameSize(_ size: NSSize) {
        let changed = size != frame.size
        // The card and its surface in one commit: a commit on any thread (e2e: a card's track) takes what the main
        // thread has changed so far, and waits for Core Animation's lock. The content's layout, after, can take a
        // frame or more.
        CATransaction.lock()
        super.setFrameSize(size)
        if chrome.frame.size != bounds.size {
            chrome.frame = bounds
            chrome.place(bounds.size)
        }
        CATransaction.unlock()
        host.frame.size = bounds.size
        if SettlingHost.record, changed {
            motionTrack.change(slides, in: window, content: host.frame.size)
        }
    }

    private func animation(_ key: String, _ from: Any, _ end: Any,
                           duration: Double = MovingCard.slide) -> CABasicAnimation
    {
        let animation = CABasicAnimation(keyPath: key)
        (animation.fromValue, animation.toValue, animation.duration) = (from, end, duration)
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }
}

extension MovingCard {
    /// Any left click on a card makes it the keyboard's card, whatever it lands on: a terminal, a web page, a plugin's
    /// error, a loader, a button, the header. AppKit's own first responder change reaches only views that take keys.
    static func activateOnClick() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated { clicked(event) }
            return event
        }
    }

    private static func clicked(_ event: NSEvent) {
        guard let window = event.window, window.attachedSheet == nil, let content = window.contentView,
              let hit = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil)
                  ?? event.locationInWindow)
        else { return }
        let card = sequence(first: hit, next: \.superview).lazy.compactMap { $0 as? MovingCard }.first
        // After AppKit's mouse-down: a view that takes keys (a field, the page, the terminal) became first responder
        // there, ahead of its own mouseDown.
        DispatchQueue.main.async {
            if let card {
                activate(card, in: window)
            } else if window.firstResponder === window, let id = floated(in: window),
                      let pages = WindowPages.windows.first(where: { $0.floats(id) })
            {
                // A floating window whose view lost the keys (a reload, a new web view) gets them back.
                pages.terminals.focus(id)
            }
        }
    }

    /// Focus follows mouse: the card under the pointer takes the keyboard once the pointer rests on it. Read from the
    /// pointer's place, not SwiftUI's hover or mouse events: while a text panel shows (an autocorrection when typing
    /// in a web page), its own tracking takes the moves and keeps the run loop in its tracking mode.
    /// ponytail: polls the pointer every 150 ms while the app is active and follow is on; start the polls from mouse
    /// events if it ever shows in energy use.
    static func followMouse() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { menus += 1 }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { menus = max(menus - 1, 0) }
        }
        Task {
            weak var last: MovingCard?, followed: MovingCard?
            var point = NSEvent.mouseLocation, parked = false
            while true {
                try? await Task.sleep(for: .milliseconds(NSApp.isActive && AppSettings().followMouse ? 150 : 1000))
                let card = AppSettings().followMouse ? underPointer() : nil
                let moved = NSEvent.mouseLocation != point
                point = NSEvent.mouseLocation
                defer { last = card }
                // A card that comes under a still pointer (an unzoom, a swap, a tab switch) waits for it to move.
                if card !== last || moved && parked {
                    (followed, parked) = moved ? (nil, false) : (card, true)
                }
                // Rested a poll on it, no button down, no open menu, no field typed in (at its end, it takes the keys).
                guard let card, card === last, card !== followed, let window = card.window,
                      NSEvent.pressedMouseButtons == 0, menus == 0, !typing(in: window) else { continue }
                followed = card
                activate(card, in: window, follow: true)
            }
        }
    }

    private static let all = NSHashTable<MovingCard>.weakObjects()
    private static var menus = 0

    /// In the main window, as a card's `appearsActive`, under panels: a closed menu's fades out over it for a moment,
    /// and an autocorrection's can be the key window. A floating pane's window over it hides its cards.
    private static func underPointer() -> MovingCard? {
        let point = NSEvent.mouseLocation
        guard NSApp.isActive,
              let window = NSApp.orderedWindows
                  .first(where: { $0.isVisible && $0.canBecomeMain && $0.frame.contains(point) }),
              window.isMainWindow, window.attachedSheet == nil else { return nil }
        // By frame, not a hit test: SwiftUI's says no view takes a click over text that takes none (a card's title).
        let inWindow = window.convertPoint(fromScreen: point)
        guard let page = WindowPages.windows.first(where: { $0.window === window })?.current else { return nil }
        // Not a closed pane's card as it fades out.
        let cards = all.allObjects.filter {
            $0.window === window && !$0.isHiddenOrHasHiddenAncestor && page.store.pane($0.id) != nil
                && $0.convert($0.bounds, to: nil).contains(inWindow)
        }
        // A zoomed card lies over the others of its tab.
        return cards.first { $0.id == page.zoomedPaneID } ?? cards.first
    }

    /// A field typed in keeps the keys (a rename, an address, the sidebar's filter), but not a chat's reply box or a
    /// blank browser's address: they are their card's keyboard view, as a terminal is.
    private static func typing(in window: NSWindow) -> Bool {
        guard let text = window.firstResponder as? NSText else { return false }
        let card = sequence(first: text as NSView, next: \.superview).lazy.compactMap { $0 as? MovingCard }.first
        guard let card, let page = WindowPages.windows.first(where: { $0.window === window })?.current,
              let pane = page.store.pane(card.id) else { return true }
        return page.renamingPaneID == card.id
            || page.shownChat(pane) == nil && page.cards(pane, make: false).0?.address.isEmpty != true
    }

    private static func floated(in window: NSWindow) -> String? {
        FloatFrames.windows.keyEnumerator().allObjects.compactMap { $0 as? String }
            .first { FloatFrames.windows.object(forKey: $0 as NSString) === window }
    }

    private static func activate(_ card: MovingCard, in window: NSWindow, follow: Bool = false) {
        guard let pages = WindowPages.windows.first(where: { $0.window === window }), !pages.panelOpen,
              !follow || pages.question == nil,
              let page = pages.current, let pane = page.store.pane(card.id), pane.tabID == page.selectedTab?.id,
              !page.floats(pane), !follow || page.keyboardCard(pane.tabID) !== pane
        else { return }
        if let responder = window.firstResponder as? NSView, responder.isDescendant(of: card),
           let terminalID = pane.terminalID
        {
            page.tookKeyboard(terminalID)
        } else {
            page.go(to: pane)
        }
    }
}
