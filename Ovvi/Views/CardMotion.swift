import AppKit
import SwiftUI

/// A card in its own hosting view, moved and sized by Core Animation: a split's, a close's, a swap's or a zoom's
/// motion runs in the render server, so a busy main thread (herdr's answer, a new terminal, a web page, other apps)
/// drops none of its frames. During the motion the card keeps the larger of its two sizes, clipped by its moving
/// frame; it lays out at its new size once the motion ends.
struct CardMotion<Content: View>: NSViewRepresentable {
    let rect: CGRect
    /// Changes with each layout that moves the cards (the tree's, the zoom's): a new place with a new value is a
    /// motion; one with the same value a resize (the window, the sidebar, a divider's drag).
    let move: Int
    /// A new card at its start beside its place: it slides in from there, fading in over half its slide.
    let entering: Bool
    let hidden: Bool
    /// Its pane, for its e2e identifier.
    let id: String
    let content: Content

    func makeNSView(context _: Context) -> MovingCard {
        let card = MovingCard(AnyView(content), move: move, rect: rect)
        card.entering = entering
        if SettlingHost.record {
            card.setAccessibilityElement(true)
            card.setAccessibilityRole(.group)
            card.setAccessibilityIdentifier("motion.\(id)")
        }
        return card
    }

    func updateNSView(_ card: MovingCard, context _: Context) {
        card.host.rootView = AnyView(content)
        card.hide(hidden)
        if move != card.move || card.entering && !entering {
            card.arm(move, to: rect, fade: card.entering)
        } else {
            card.rect = rect
        }
        card.entering = entering
    }
}

final class MovingCard: NSView {
    let host: NSHostingView<AnyView>
    private(set) var move: Int
    /// Its place in the page as last given.
    var rect: CGRect
    var entering = false
    /// The card's size where the motion under way started: it keeps the larger size until it ends.
    private var from: CGSize?
    private var motions = 0
    /// e2e (`-recordMotion YES`): the motions it made, as its accessibility label ("slides 3").
    private var slides = 0

    init(_ content: AnyView, move: Int, rect: CGRect) {
        host = NSHostingView(rootView: content)
        (self.move, self.rect) = (move, rect)
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    /// Moves from where the card shows now (its last place, or where a motion under way has it) to `rect`, whether
    /// SwiftUI sets its new frame before this or after.
    func arm(_ move: Int, to rect: CGRect, fade: Bool) {
        let old = self.rect
        (self.move, self.rect) = (move, rect)
        guard let layer, old.width > 0 else { return }
        var size = old.size, offset = CGPoint(x: old.minX - rect.minX, y: old.minY - rect.minY)
        if let shown = layer.presentation(), layer.animation(forKey: "motion.position") != nil {
            size = shown.bounds.size
            offset.x += shown.position.x - layer.position.x
            offset.y += shown.position.y - layer.position.y
        }
        guard size != rect.size || offset != .zero else { return }
        from = size
        host.frame = CGRect(origin: .zero, size: CGSize(width: max(size.width, rect.width),
                                                        height: max(size.height, rect.height)))
        layer.anchorPoint = .zero
        layer.masksToBounds = true
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        let position = animation("position", NSValue(point: offset), NSValue(point: .zero))
        position.isAdditive = true
        var animations = [animation("bounds.size", NSValue(size: size), NSValue(size: rect.size)), position]
        if fade {
            animations.append(animation("opacity", 0, 1, duration: TabPage.slide / 2))
        }
        motions += 1
        let motion = motions
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, motion == motions else { return }
            from = nil
            layer.masksToBounds = false
            layer.cornerRadius = 0
            host.frame = bounds
        }
        for animation in animations {
            layer.add(animation, forKey: "motion.\(animation.keyPath ?? "")")
        }
        CATransaction.commit()
        if SettlingHost.record {
            slides += 1
            setAccessibilityLabel("slides \(slides)")
        }
    }

    /// Hidden in a kept page out of view: no mouse moves or accessibility reach it.
    func hide(_ hidden: Bool) {
        if hidden != isHidden {
            isHidden = hidden
        }
    }

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        let from = from ?? .zero
        host.frame = CGRect(origin: .zero, size: CGSize(width: max(from.width, bounds.width),
                                                        height: max(from.height, bounds.height)))
    }

    private func animation(_ key: String, _ from: Any, _ end: Any,
                           duration: Double = TabPage.slide) -> CABasicAnimation
    {
        let animation = CABasicAnimation(keyPath: key)
        (animation.fromValue, animation.toValue, animation.duration) = (from, end, duration)
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }
}
