import AppKit
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
    /// Every card's motion: ease-out, no overshoot. 0.2 s felt slow.
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
        if SettlingHost.record {
            slides += 1
            setAccessibilityLabel("slides \(slides)")
            track()
            // How far each edge goes (left, top, right, bottom): a busy main thread may sample only the motion's end.
            let edges = [-offset.x, offset.y - rect.height + size.height, -offset.x + rect.width - size.width, offset.y]
            span = zip(span, edges).map { max($0, Int(abs($1).rounded())) }
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

    /// e2e: the card's place at each display frame, from a change until 0.4 s after the last one, in the window
    /// content's layer; the frames its surface was off the card by over a point; its content's laid out sizes.
    /// Each sample after the first is its change from the one before: an element's label holds 512 characters.
    /// "slides N span l t r b surface K content 1420x1030 706x1030 track ms x y w h;dms dx dy dw dh;…".
    private var samples: [[Int]] = [], sampler: CADisplayLink?, sampled = (start: 0.0, changed: 0.0)
    private var surfaceOff = 0, contents: [String] = [], span = [0, 0, 0, 0]

    private func track() {
        let now = CACurrentMediaTime()
        sampled.changed = now
        guard sampler == nil else { return }
        (samples, surfaceOff, contents, span, sampled.start) = ([], 0, [], [0, 0, 0, 0], now)
        // The screen's, not the view's: a new card's view has no window yet.
        sampler = (window?.screen ?? NSScreen.main)?.displayLink(target: self, selector: #selector(sample))
        sampler?.add(to: .main, forMode: .common)
    }

    @objc private func sample(_: CADisplayLink) {
        let now = CACurrentMediaTime()
        defer { stopTracking(now) }
        guard let layer, let shown = layer.presentation(), let root = window?.contentView?.layer,
              let rootShown = root.presentation() else { return }
        let card = shown.convert(shown.bounds, to: rootShown), surface = chrome.shownFill(in: rootShown) ?? .zero
        let place = [card.minX, card.minY, card.width, card.height].map { Int($0.rounded()) }
        if samples.last.map({ Array($0.dropFirst()) }) != place {
            samples.append([Int((now - sampled.start) * 1000)] + place)
            sampled.changed = max(sampled.changed, now)
        }
        if [card.minX - surface.minX, card.minY - surface.minY, card.maxX - surface.maxX, card.maxY - surface.maxY]
            .contains(where: { abs($0) > 1 })
        {
            surfaceOff += 1
        }
        let content = "\(Int(host.frame.width))x\(Int(host.frame.height))"
        if contents.last != content {
            contents.append(content)
        }
    }

    private func stopTracking(_ now: Double) {
        if now - sampled.changed > 0.4 {
            sampler?.invalidate()
            sampler = nil
            let steps = zip([[]] + samples, samples).map { before, now in
                (before.isEmpty ? now : zip(now, before).map { $0 - $1 }).map(String.init).joined(separator: " ")
            }
            setAccessibilityLabel("slides \(slides) span \(span.map(String.init).joined(separator: " ")) surface "
                + "\(surfaceOff) content \(contents.joined(separator: " ")) "
                + "track \(steps.joined(separator: ";"))")
        }
    }

    /// A card that leaves its window mid-track: its display link would keep it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            sampler?.invalidate()
            sampler = nil
        }
    }

    override func setFrameOrigin(_ origin: NSPoint) {
        if SettlingHost.record, origin != frame.origin {
            track()
        }
        super.setFrameOrigin(origin)
    }

    override func setFrameSize(_ size: NSSize) {
        if SettlingHost.record, size != frame.size {
            track()
        }
        super.setFrameSize(size)
        host.frame.size = bounds.size
        if chrome.frame.size != bounds.size {
            chrome.frame = bounds
            chrome.place(bounds.size)
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

    private static func floated(in window: NSWindow) -> String? {
        FloatFrames.windows.keyEnumerator().allObjects.compactMap { $0 as? String }
            .first { FloatFrames.windows.object(forKey: $0 as NSString) === window }
    }

    private static func activate(_ card: MovingCard, in window: NSWindow) {
        guard let pages = WindowPages.windows.first(where: { $0.window === window }), !pages.panelOpen,
              let page = pages.current, let pane = page.store.pane(card.id), pane.tabID == page.selectedTab?.id,
              !page.floats(pane)
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
