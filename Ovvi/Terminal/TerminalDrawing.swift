import CoreImage
import GhosttyTerminal
import HerdrKit
import IOSurface
import SwiftUI

extension PaneTerminal {
    /// The app's paste mode; no cursor until herdr's first frame says whether it shows.
    static let modes = "\u{1B}[?2004h\u{1B}[?25l"

    /// Called ahead of libghostty hearing of a grid change: its renderer thread may draw at once (CI: garbled glyphs
    /// for 3 frames after a ⌘- paused late). A watcher shows the reflow: it cannot resize.
    func hold() {
        guard ready, !observing else { return }
        ready = false
        // libghostty can draw during the hold.
        view.holdPicture()
        settle()
    }

    /// libghostty's layer keeps its last picture at the top left (its layer gravity), or nothing on a new surface (its
    /// background is clear). Not an alpha hide: the text goes blank between two pictures.
    func settle() {
        // A rebuilt watcher settles too: its new surface has not parsed the first frame when that reveal would
        // draw.
        if observing, view.still == nil {
            return reveal()
        }
        view.setSurfaceVisible(false)
        // A program that redraws all the time never settles. Under the waiting spinner's 0.5 s.
        deadline = deadline ?? Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled {
                reveal()
            }
        }
        settling?.cancel()
        settling = Task {
            try? await Task.sleep(for: .milliseconds(100))
            if !Task.isCancelled {
                reveal()
            }
        }
    }

    /// libghostty took a new grid: until herdr's frame at that size replaces it, the surface holds libghostty's own
    /// reflow of the old screen (rows joined or cut at the new width), which a settle timed from the hold showed when
    /// herdr answered late (a busy Mac, a remote machine). At most 1 s: herdr answers every resize.
    func awaitAnswer(columns: Int, rows: Int) {
        guard !ready, !observing else { return }
        unanswered = (columns, rows)
        deadline?.cancel()
        deadline = nil
        settling?.cancel()
        settling = Task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled {
                reveal()
            }
        }
    }

    /// herdr's answer is the old screen at the new size; the program's redraw follows in later frames (in one for a
    /// program that synchronizes its output), so the answer only starts the deadline. Other sizes' frames do not
    /// count.
    func settle(after frame: TerminalStream.Frame) {
        guard let size = unanswered else { return settle() }
        guard frame.width == size.columns, frame.height == size.rows else { return }
        unanswered = nil
        settling?.cancel()
        deadline = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled {
                reveal()
            }
        }
    }

    func inViewChanged() {
        if !inView {
            if PaneViewRegistry.recent.contains(where: { $0 === self }) {
                view.keepPicture()
            }
            takeSnapshot()
        }
        if ready {
            draw()
        }
    }

    func draw() {
        view.setSurfaceVisible(inView)
        if inView {
            view.dropStill()
        }
    }

    /// herdr has no call for a repaint: the PTY one column narrower, then the card's grid back, two SIGWINCHes; TUIs
    /// repaint all at a new width. Not while watching: observe cannot resize.
    func redraw() {
        guard state == .live, redrawing == nil, let grid, grid.columns > 1 else { return }
        hold()
        resize(columns: Int(grid.columns) - 1, rows: Int(grid.rows))
        redrawing = Task { [generation] in
            // The program has read the narrow size and drawn at it: frames paused for 150 ms, from 250 ms on (a
            // program that reads the size only after both changes sees none), at most 1 s.
            let start = ContinuousClock.now
            while start.duration(to: .now) < .seconds(1), start.duration(to: .now) < .milliseconds(250)
                || lastFrame.duration(to: .now) < .milliseconds(150)
            {
                try? await Task.sleep(for: .milliseconds(50))
            }
            redrawing = nil
            guard generation == self.generation, state == .live, let grid = self.grid else { return }
            resize(columns: Int(grid.columns), rows: Int(grid.rows))
            awaitAnswer(columns: Int(grid.columns), rows: Int(grid.rows))
        }
    }

    /// The first fades in from 0: a fade that never runs leaves it shown.
    private func reveal() {
        settling?.cancel()
        deadline?.cancel()
        deadline = nil
        guard redrawing == nil else { return }
        unanswered = nil
        ready = true
        Latency.shared.step("ready")
        draw()
        let first = !revealed
        revealed = true
        if first, !(view.superview is MiniTerminal.Mini),
           !Animation.reduced
        {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.duration = 0.06
            view.layer?.add(fade, forKey: "reveal")
        }
    }
}

/// An IOSurface: Core Animation shows it without a copy of its own (a `CGImage` doubles the memory).
extension PaneTerminal {
    /// Least recently taken or shown in a tile first out, past the bound: a full-window card's is about 1.3–1.7 MB on
    /// Retina, so about 200 tiles.
    static var snapshots: [PaneTerminal] = []
    static let snapshotBytes = 320 << 20
    private static let context = CIContext(options: [.cacheIntermediates: false])

    var pictured: Bool {
        snapshot != nil || inView && ready || state.isFailed
    }

    func takeSnapshot() {
        // Not of its snapshot standing in for a tile that has not drawn: it would shrink at each turn.
        guard let surface = view.picture as? IOSurface, !surface.emptied, surface !== snapshot else { return }
        let space = IOSurfaceCopyValue(surface, kIOSurfaceColorSpace), scale = min(1, view.tileScale())
        // Bilinear: Lanczos cost a few ms more on every tab switch, for a picture shown a moment.
        let image = CIImage(ioSurface: surface).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let size = image.extent.integral
        guard let small = IOSurface(properties: [
            .width: Int(size.width), .height: Int(size.height), .bytesPerElement: 4,
            .pixelFormat: surface.pixelFormat,
        ]) else { return }
        if let space {
            IOSurfaceSetValue(small, kIOSurfaceColorSpace, space)
        }
        Self.context.render(image, to: small, bounds: size,
                            colorSpace: space.flatMap { CGColorSpace(propertyListPlist: $0) })
        snapshot = small
        snapshotShown()
        Self.trimSnapshots(Self.snapshotBytes)
    }

    func snapshotShown() {
        guard snapshot != nil else { return }
        Self.snapshots.removeAll { $0 === self }
        Self.snapshots.append(self)
    }

    static func trimSnapshots(_ most: Int) {
        while snapshots.reduce(0, { $0 + ($1.snapshot?.allocationSize ?? 0) }) > most {
            let old = snapshots.removeFirst()
            if let still = old.view.still, still.superlayer == nil, still.contents as AnyObject? === old.snapshot {
                old.view.still = nil
                old.revealed = false
            }
            old.snapshot = nil
        }
    }
}

/// libghostty's three IOSurfaces of the card's size take 17 MB each for a full-window card on a Retina screen. Its last
/// picture stays in libghostty's layer, volatile while no window shows it, so that it costs no memory then (the system
/// may take it back under memory pressure).
extension PaneSurfaceView {
    func free() {
        guard controller != nil else { return }
        // A still not dropped yet (evicted again ahead of its new surface's first draw) stays the picture.
        still = still ?? layer
        controller = nil
        purgeable(window == nil)
    }

    func dropPicture() {
        lowerStill()
        if still !== layer {
            still?.removeFromSuperlayer()
        }
        still = terminal?.snapshot.map { snapshot in
            let layer = CALayer()
            layer.contents = snapshot
            layer.contentsGravity = .resize
            return layer
        }
        layer?.contents = nil
        terminal?.revealed = still != nil
    }

    func rebuild() {
        guard controller == nil else { return }
        purgeable(false)
        Latency.shared.step("surface")
        controller = PaneTerminal.controller
    }

    var picture: Any? {
        still?.superlayer == nil ? layer?.contents : still?.contents
    }

    /// libghostty draws when it stops being occluded. An empty frame does not count (a swap chain made again at a new
    /// size can show one first), unless three come: the screen is empty.
    func dropStill() {
        // Over a new surface only, not the view's own layer ahead of its rebuild.
        guard let still, still !== layer, still.superlayer != nil else { return }
        let id = ObjectIdentifier(still)
        stillFrames = 0
        // libghostty sets the contents on the main thread: gone in the same transaction as the new picture.
        stillWatch = layer?.observe(\.contents) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let view = self else { return }
                view.stillFrames += 1
                if (view.layer?.contents as? IOSurface)?.drawn == true || view.stillFrames >= 3 {
                    view.drop(id)
                }
            }
        }
    }

    private func drop(_ id: ObjectIdentifier) {
        guard let old = still, ObjectIdentifier(old) == id else { return }
        // At once, in the new picture's transaction: no fade of the old over it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        old.removeFromSuperlayer()
        layer?.opacity = 1
        CATransaction.commit()
        still = nil
        stillWatch = nil
    }

    func coverNewSurface() {
        lowerStill()
        dropSmallStill()
        if let still, let layer, still !== layer {
            still.frame = layer.bounds
            still.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            // A new sublayer fades in by itself: not with Reduce Motion or Animations off.
            CATransaction.begin()
            CATransaction.setDisableActions(Animation.reduced)
            layer.addSublayer(still)
            CATransaction.commit()
        }
        guard let terminal, terminal.grid != nil else { return }
        // A settle begun while evicted (a resize) would reveal the empty surface.
        terminal.settling?.cancel()
        terminal.deadline?.cancel()
        terminal.deadline = nil
        terminal.ready = false
        setSurfaceVisible(false)
        if terminal.state != .idle {
            terminal.settle()
        }
    }

    /// Out of a miniature, a still smaller than the view's pixels shows blurred, then sharp: the card shows its fill
    /// instead.
    func dropSmallStill() {
        // Only a snapshot's (stretched): a full-size still of a card that grew meanwhile shows unscaled.
        guard !(superview is MiniTerminal.Mini), let still, still !== layer, still.contentsGravity == .resize,
              still.small(in: self) else { return }
        still.removeFromSuperlayer()
        self.still = nil
        stillWatch = nil
        terminal?.revealed = false
    }

    /// Back in a window, a picture the system took is gone (it takes them within seconds).
    func purgeable(_ volatile: Bool) {
        // Not a snapshot standing in: the overview's tiles show it too.
        guard controller == nil, let surface = still?.contents as? IOSurface, surface !== terminal?.snapshot
        else { return }
        var old: UInt32 = 0
        IOSurfaceSetPurgeable(surface, volatile ? 1 : 0, &old)
        if !volatile, old == IOSurfacePurgeabilityState.purgeableEmpty.rawValue {
            still?.removeFromSuperlayer()
            still = nil
            terminal?.revealed = false
        }
    }

    /// libghostty frees its swap chain while it does not draw and empties those IOSurfaces as it frees them
    /// (`kIOSurfacePurgeableEmpty`), so that the layer's own picture is gone when the view is in a window again. About
    /// 2 ms and 17 MB for a full-window card on Retina.
    func keepPicture() {
        guard still == nil, let layer, let surface = layer.contents as? IOSurface, !surface.emptied,
              let copy = Self.copy(surface) else { return }
        let still = CALayer()
        still.contents = copy
        still.contentsGravity = layer.contentsGravity
        still.contentsScale = layer.contentsScale
        still.frame = layer.bounds
        still.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.addSublayer(still)
        CATransaction.commit()
        self.still = still
    }

    /// `hold`'s still goes over the view, in its host, and the view's own layer hides until the new picture drops the
    /// still: both have a clear background, so a still in the layer showed both screens at once while libghostty drew
    /// the new one under it.
    func holdPicture() {
        guard still == nil else { return }
        keepPicture()
        guard let still, let layer, let host = superview?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        still.frame = host.convert(layer.bounds, from: layer)
        still.autoresizingMask = []
        host.addSublayer(still)
        layer.opacity = 0
        CATransaction.commit()
    }

    /// A held still back in the view's own layer, shown with it: the view moved to another host, or its surface goes.
    func lowerStill() {
        guard let layer, layer.opacity == 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let still, still !== layer, still.superlayer !== layer {
            still.frame = layer.bounds
            still.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.addSublayer(still)
        }
        layer.opacity = 1
        CATransaction.commit()
    }

    private static func copy(_ surface: IOSurface) -> IOSurface? {
        guard let copy = IOSurface(properties: [
            .width: surface.width, .height: surface.height, .bytesPerElement: surface.bytesPerElement,
            .bytesPerRow: surface.bytesPerRow, .pixelFormat: surface.pixelFormat,
        ]) else { return nil }
        if let space = IOSurfaceCopyValue(surface, kIOSurfaceColorSpace) {
            IOSurfaceSetValue(copy, kIOSurfaceColorSpace, space)
        }
        surface.lock(options: .readOnly, seed: nil)
        copy.lock(options: [], seed: nil)
        let row = min(surface.bytesPerRow, copy.bytesPerRow)
        for line in 0 ..< surface.height {
            memcpy(copy.baseAddress + line * copy.bytesPerRow, surface.baseAddress + line * surface.bytesPerRow, row)
        }
        copy.unlock(options: [], seed: nil)
        surface.unlock(options: .readOnly, seed: nil)
        return copy
    }
}
