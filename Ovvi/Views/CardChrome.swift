import AppKit
import SwiftUI

/// `CardSurface` as Core Animation layers, for a card that `CardMotion` moves: the render server draws its fill, rim,
/// edge and shadow at each frame's size, exactly as at rest. A SwiftUI surface, laid out once for the motion, would
/// be cut by the motion's clip, and its rim and edge would change for the slide and back at landing.
final class CardChrome: NSView {
    private let fill = CALayer(), lit = CALayer(), rim = CALayer(), rimAll = CALayer(), rimTop = CALayer()
    private let topFade = CAGradientLayer(), glow = CAGradientLayer(), edge = CALayer(), drop = CALayer()
    private let shadowCut = CAShapeLayer()
    private var edgeWidth: CGFloat = 0, size = CGSize.zero

    init() {
        super.init(frame: .zero)
        // Its own layer tree (a layer-hosting view).
        let root = CALayer()
        layer = root
        wantsLayer = true
        root.sublayers = [drop, fill, lit, rim, edge]
        (drop.shadowOpacity, drop.shadowRadius) = (1, Look.dropRadius)
        drop.shadowOffset = CGSize(width: 0, height: Look.dropDown)
        for part in [fill, lit, rim, rimAll, rimTop, edge] {
            part.cornerCurve = .continuous
            part.cornerRadius = CardSurface.radius
        }
        for part in [fill, lit, rim, rimAll, rimTop, edge, topFade, glow, drop, shadowCut] {
            part.anchorPoint = .zero
        }
        rim.masksToBounds = true
        rim.compositingFilter = "plusL"
        rim.sublayers = [rimAll, rimTop, glow]
        rimAll.borderWidth = 0.7
        rimTop.borderWidth = 1
        rimTop.mask = topFade
        topFade.colors = [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)]
        drop.mask = shadowCut
        shadowCut.fillRule = .evenOdd
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    /// The look's colors, the keyboard card's fill and edge when `keyboard`.
    func paint(_ look: Look, keyboard: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let color = { (color: Color) in NSColor(color).cgColor }
        let rimColors = look.rim, edgeLook = look.edge(keyboard: keyboard)
        fill.backgroundColor = color(look.cardFill)
        lit.backgroundColor = color(look.keyboardFill)
        rimAll.borderColor = color(rimColors.all)
        rimTop.borderColor = color(rimColors.top)
        glow.colors = [color(rimColors.top.opacity(0.45)), CGColor(gray: 0, alpha: 0)]
        edge.borderColor = color(edgeLook.color)
        edgeWidth = edgeLook.width
        edge.borderWidth = edgeLook.width
        edge.cornerRadius = CardSurface.radius + edgeLook.width
        // A part a look does not draw is no pass of the render server.
        lit.isHidden = !keyboard
        rim.isHidden = look.style == .classic
        drop.isHidden = look.cardDrop == nil
        drop.shadowColor = look.cardDrop.map(color)
        CATransaction.commit()
        // The edge's width may have changed.
        place(size)
    }

    /// At the card's size, with no animation.
    func place(_ size: CGSize) {
        self.size = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (part, frame) in frames(size) {
            part.position = frame.origin
            part.bounds.size = frame.size
        }
        drop.shadowPath = path(size)
        shadowCut.path = cut(size)
        CATransaction.commit()
    }

    /// From one size to another, as the card's own motion.
    func animate(from old: CGSize, to new: CGSize, _ animation: (String, Any, Any) -> CABasicAnimation) {
        for ((part, start), (_, end)) in zip(frames(old), frames(new)) {
            part.add(animation("bounds.size", NSValue(size: start.size), NSValue(size: end.size)), forKey: "motion")
        }
        drop.add(animation("shadowPath", path(old), path(new)), forKey: "motion.path")
        shadowCut.add(animation("path", cut(old), cut(new)), forKey: "motion")
    }

    /// e2e: where its fill shows now, in that layer's space.
    func shownFill(in root: CALayer) -> CGRect? {
        fill.presentation().map { $0.convert($0.bounds, to: root) }
    }

    private func frames(_ size: CGSize) -> [(CALayer, CGRect)] {
        let card = CGRect(origin: .zero, size: size)
        return [(fill, card), (lit, card), (rim, card), (rimAll, card), (rimTop, card), (drop, card),
                (edge, card.insetBy(dx: -edgeWidth, dy: -edgeWidth)),
                (glow, CGRect(x: 0, y: 0, width: size.width, height: 8)),
                (topFade, CGRect(x: 0, y: 0, width: size.width, height: 14))]
    }

    private func path(_ size: CGSize) -> CGPath {
        CGPath(roundedRect: CGRect(origin: .zero, size: size),
               cornerWidth: CardSurface.radius, cornerHeight: CardSurface.radius, transform: nil)
    }

    /// The drop's mask: all but the card, as `CardSurface` cuts its drop from under its translucent fill.
    private func cut(_ size: CGSize) -> CGPath {
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40))
        path.addRoundedRect(in: CGRect(origin: .zero, size: size), cornerWidth: CardSurface.radius,
                            cornerHeight: CardSurface.radius)
        return path
    }
}

/// A card whose surface `CardChrome` draws: the card tells it when it is the keyboard card, and draws none itself.
final class ChromeLink {
    weak var card: MovingCard?

    init(_ card: MovingCard) {
        self.card = card
    }
}

extension EnvironmentValues {
    @Entry var chromeLink: ChromeLink?
}
