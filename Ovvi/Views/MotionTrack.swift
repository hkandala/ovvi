import AppKit

/// e2e (`recordMotion`): a card's place at each display frame, from a change until 0.4 s after the last one, in the
/// window content's layer; the frames its surface was off the card by over a point; its content's laid out sizes.
/// Sampled on its own thread, as the render server moves the card: the main thread can be busy for a whole motion
/// (on CI, herdr's answers to a split took it for up to 380 ms of a 130 ms slide).
/// Each sample after the first is its change from the one before: an element's label holds 512 characters.
/// "slides N span l t r b surface K content 1420x1030 706x1030 track ms x y w h;dms dx dy dw dh;…".
final nonisolated class MotionTrack: NSObject, @unchecked Sendable {
    private let lock = NSLock(), card: CALayer, surface: CALayer, show: @MainActor @Sendable (String) -> Void
    /// The window content's layer: a new card has no window at its first change.
    private var root: CALayer?
    private var link: CADisplayLink?, start = 0.0, changed = 0.0, slides = 0
    private var samples: [[Int]] = [], span = [0, 0, 0, 0], surfaceOff = 0, contents: [String] = []

    init(card: CALayer, surface: CALayer, show: @escaping @MainActor @Sendable (String) -> Void) {
        (self.card, self.surface, self.show) = (card, surface, show)
    }

    /// A change of the card: starts a track, or keeps the running one going. `edges`: how far a motion takes each
    /// edge (left, top, right, bottom), for a track that saw only its end.
    @MainActor func change(_ slides: Int, in window: NSWindow?, content: CGSize, edges: [CGFloat] = []) {
        let now = CACurrentMediaTime(), size = "\(Int(content.width))x\(Int(content.height))"
        let root = window?.contentView?.layer
        let new = lock.withLock {
            let new = link == nil
            if new {
                (samples, surfaceOff, contents, span, start) = ([], 0, [], [0, 0, 0, 0], now)
            }
            (changed, self.slides, self.root) = (now, slides, root ?? self.root)
            if contents.last != size {
                contents.append(size)
            }
            span = zip(span, edges + [0, 0, 0, 0]).map { max($0, Int(abs($1).rounded())) }
            return new
        }
        guard new else { return }
        // The screen's, not the view's: a new card's view has no window yet.
        guard let link = (window?.screen ?? NSScreen.main)?.displayLink(target: self, selector: #selector(sample))
        else { return }
        lock.withLock { self.link = link }
        Self.add(link)
    }

    /// A card that leaves its window samples no more; a new card samples once it has one.
    @MainActor func moved(to window: NSWindow?) {
        let root = window?.contentView?.layer
        lock.withLock { self.root = root }
    }

    /// On the loop's own thread, as a run loop asks; not in `change`, whose closures would run on the main actor.
    private static func add(_ link: CADisplayLink) {
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { link.add(to: .current, forMode: .common) }
        CFRunLoopWakeUp(loop)
    }

    /// The tracks' own thread, which runs their display links.
    private nonisolated(unsafe) static let loop: CFRunLoop = {
        nonisolated(unsafe) var loop: CFRunLoop?
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            loop = CFRunLoopGetCurrent()
            // Keeps the loop running while no link is in it.
            RunLoop.current.add(NSMachPort(), forMode: .common)
            ready.signal()
            RunLoop.current.run()
        }
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return loop ?? CFRunLoopGetMain()
    }()

    /// Core Animation's lock is taken outside this one: the main thread changes the card inside its transactions.
    @objc private func sample(_: CADisplayLink) {
        let now = CACurrentMediaTime(), root = lock.withLock { self.root }
        var place: [Int]?, off = false
        // Values that hold together across the card, its fill and the window's layer.
        CATransaction.lock()
        // Not in a motion's first frame: until its commit its begin is 0 and the card shows its end place, and in the
        // 1/60 s from it a read saw the motion on the card's old place, which a 60 fps film of the screen never showed.
        // `bounds.size` is the first of a motion's keys that arm adds.
        let begin = card.animation(forKey: "motion.bounds.size").map {
            $0.beginTime == 0 ? now : card.convertTime($0.beginTime, to: nil)
        }
        if let root, begin.map({ now - $0 >= 1.0 / 60 }) ?? true, let shown = card.presentation(),
           let rootShown = root.presentation()
        {
            let card = shown.convert(shown.bounds, to: rootShown)
            let fill = surface.presentation().map { $0.convert($0.bounds, to: rootShown) } ?? .zero
            place = [card.minX, card.minY, card.width, card.height].map { Int($0.rounded()) }
            off = [card.minX - fill.minX, card.minY - fill.minY, card.maxX - fill.maxX, card.maxY - fill.maxY]
                .contains { abs($0) > 1 }
        }
        CATransaction.unlock()
        let (label, ended): (String?, CADisplayLink?) = lock.withLock {
            if let place, samples.last.map({ Array($0.dropFirst()) }) != place {
                samples.append([Int((now - start) * 1000)] + place)
                changed = max(changed, now)
            }
            surfaceOff += off ? 1 : 0
            guard now - changed > 0.4 else { return (nil, nil) }
            let ended = link
            link = nil
            let steps = zip([[]] + samples, samples).map { before, now in
                (before.isEmpty ? now : zip(now, before).map { $0 - $1 }).map(String.init).joined(separator: " ")
            }
            return ("slides \(slides) span \(span.map(String.init).joined(separator: " ")) surface \(surfaceOff) "
                + "content \(contents.joined(separator: " ")) track \(steps.joined(separator: ";"))", ended)
        }
        ended?.invalidate()
        if let label {
            DispatchQueue.main.async { self.show(label) }
        }
    }
}
