import AppKit
import SwiftUI

/// Moved and sized by Core Animation: the motion runs in the render server, so a busy main thread (herdr's answer, a
/// new terminal, a web page, other apps) drops none of its frames.
struct CardMotion<Content: View>: NSViewRepresentable {
    let rect: CGRect
    let move: Int
    let entering: Bool
    let hidden: Bool
    let id: String
    let edge: (color: NSColor, width: CGFloat)
    let content: Content

    func makeNSView(context _: Context) -> MovingCard {
        let card = MovingCard(AnyView(content), move: move, rect: rect)
        card.entering = entering
        if SettlingHost.record {
            card.setAccessibilityElement(true)
            card.setAccessibilityRole(.group)
        }
        return card
    }

    func updateNSView(_ card: MovingCard, context _: Context) {
        card.host.rootView = AnyView(content)
        card.edge = edge
        card.hide(hidden)
        if SettlingHost.record {
            card.setAccessibilityIdentifier("motion.\(id)")
        }
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
    var rect: CGRect
    var entering = false
    var edge = (color: NSColor.clear, width: CGFloat(0))
    private var from: CGSize?
    private var motions = 0
    private var slides = 0

    init(_ content: AnyView, move: Int, rect: CGRect) {
        host = NSHostingView(rootView: content)
        (self.move, self.rect) = (move, rect)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = CardSurface.radius
        layer?.cornerCurve = .continuous
        host.safeAreaRegions = []
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    /// SwiftUI sets the card's new frame ahead of this call or after it.
    func arm(_ move: Int, to rect: CGRect, fade: Bool) {
        let old = self.rect
        (self.move, self.rect) = (move, rect)
        guard let layer, old.width > 0 else { return }
        // The superlayer's y grows upward.
        var size = old.size, offset = CGPoint(x: old.minX - rect.minX, y: rect.maxY - old.maxY)
        if let shown = layer.presentation(), layer.animation(forKey: "motion.position") != nil {
            size = shown.bounds.size
            offset.x += shown.position.x - layer.position.x
            offset.y += shown.position.y - layer.position.y
        }
        guard size != rect.size || offset != .zero else { return }
        from = size
        host.frame = CGRect(origin: .zero, size: CGSize(width: max(size.width, rect.width),
                                                        height: max(size.height, rect.height)))
        layer.masksToBounds = true
        // The card's edge, which it draws just outside its shape, where the mask cuts it.
        (layer.borderWidth, layer.borderColor) = (edge.width, edge.color.cgColor)
        let position = animation("position", NSValue(point: offset), NSValue(point: .zero))
        position.isAdditive = true
        var animations = [animation("bounds.size", NSValue(size: size), NSValue(size: rect.size)), position]
        if fade {
            animations.append(animation("opacity", 0, 1, duration: HostStore.slide / 2))
        }
        motions += 1
        let motion = motions
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, motion == motions else { return }
            from = nil
            layer.masksToBounds = false
            layer.borderWidth = 0
            host.frame = bounds
        }
        for animation in animations {
            layer.add(animation, forKey: "motion.\(animation.keyPath ?? "")")
        }
        CATransaction.commit()
        if SettlingHost.record {
            slides += 1
            setAccessibilityLabel("slides \(slides)")
            let start = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.asyncAfter(deadline: .now() + HostStore.slide / 2) { [weak self] in
                self?.recordMid(since: start)
            }
        }
    }

    private func recordMid(since start: TimeInterval) {
        guard let layer, let shown = layer.presentation(), let window, let content = window.contentView,
              let root = content.layer, let rootShown = root.presentation() else { return }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let onScreen = { (rect: CGRect) -> String in
            let frame = window.convertToScreen(content.convert(rect, to: nil))
            return [frame.minX, top - frame.maxY, frame.width, frame.height].map { "\(Int($0.rounded()))" }
                .joined(separator: " ")
        }
        let mid = shown.convert(shown.bounds, to: rootShown), end = layer.convert(layer.bounds, to: root)
        let time = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
        setAccessibilityLabel("slides \(slides) mid \(onScreen(mid)) at \(time) end \(onScreen(end))")
    }

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        let from = from ?? .zero
        host.frame = CGRect(origin: .zero, size: CGSize(width: max(from.width, bounds.width),
                                                        height: max(from.height, bounds.height)))
    }

    private func animation(_ key: String, _ from: Any, _ end: Any,
                           duration: Double = HostStore.slide) -> CABasicAnimation
    {
        let animation = CABasicAnimation(keyPath: key)
        (animation.fromValue, animation.toValue, animation.duration) = (from, end, duration)
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return animation
    }
}
