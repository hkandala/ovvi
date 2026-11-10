import AppKit

/// Fits the view to itself once its size stops changing: meanwhile the terminal keeps its grid, clipped, so neither
/// libghostty nor the program reflows at every step, and a web view does not lay its page out at every step. In a
/// card's motion at once: the card lays its content out once, at its final size.
final class SettlingHost: NSView {
    private var fitting: Task<Void, Never>?
    static let record = UserDefaults.standard.bool(forKey: "recordMotion")
    private var sizes = 0, motion: (start: TimeInterval, last: TimeInterval)?

    override var isFlipped: Bool {
        true
    }

    override func resizeSubviews(withOldSize old: NSSize) {
        guard frame.size != old else { return }
        if Self.record {
            sizes += 1
            let now = ProcessInfo.processInfo.systemUptime
            let start = motion.map { now - $0.last < 0.1 ? $0.start : now } ?? now
            motion = (start, now)
            setAccessibilityLabel("\(sizes) \(Int((now - start) * 1000))")
        }
        fitting?.cancel()
        let moving = sequence(first: self) { $0.superview }.lazy.compactMap { $0 as? MovingCard }.first?.moving == true
        let surface = view as? PaneSurfaceView
        guard let view, surface == nil || surface?.terminal?.grid != nil, !view.frame.isEmpty, old != .zero, !moving
        else {
            fit()
            return
        }
        Self.settle(&fitting) { self.fit() }
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        fitting?.cancel()
        fit()
    }

    private var view: NSView? {
        subviews.first
    }

    func fit() {
        guard let view, !bounds.isEmpty, view.frame.size != bounds.size else { return }
        Self.place(view, bounds)
        // e2e: "sizes ms fit ms", the fit's time from the first size of its run.
        if Self.record, let motion {
            let fitted = Int((ProcessInfo.processInfo.systemUptime - motion.start) * 1000)
            setAccessibilityLabel("\(sizes) \(Int((motion.last - motion.start) * 1000)) fit \(fitted)")
        }
    }

    static func settle(_ fitting: inout Task<Void, Never>?, _ fit: @escaping @MainActor () -> Void) {
        fitting?.cancel()
        fitting = Task {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled {
                fit()
            }
        }
    }

    /// A terminal holds its frames ahead of libghostty hearing of the size.
    static func place(_ view: NSView, _ frame: CGRect) {
        (view as? PaneSurfaceView)?.terminal?.hold()
        view.frame = frame
    }
}

extension NSView {
    /// The keyboard leaves it first, to the window: AppKit would hand it to the next key view, which would claim it.
    func hide(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        if hidden, let window, let responder = window.firstResponder as? NSView, responder.isDescendant(of: self) {
            window.makeFirstResponder(nil)
        }
        isHidden = hidden
    }
}
