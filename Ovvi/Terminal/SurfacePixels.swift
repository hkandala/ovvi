import AppKit
import IOSurface

extension CALayer {
    func small(in view: NSView) -> Bool {
        guard let scale = view.window?.backingScaleFactor,
              let surface = contents as? IOSurface else { return false }
        return CGFloat(surface.width) < view.bounds.width * scale - 1
    }
}

extension IOSurface {
    var drawn: Bool {
        guard bytesPerElement == 4, width > 0, height > 0 else { return false }
        lock(options: .readOnly, seed: nil)
        defer { unlock(options: .readOnly, seed: nil) }
        let background = baseAddress.load(as: UInt32.self)
        for line in stride(from: 0, to: height, by: 2) {
            let pixels = (baseAddress + line * bytesPerRow).assumingMemoryBound(to: UInt32.self)
            if (0 ..< width).contains(where: { pixels[$0] != background }) {
                return true
            }
        }
        return false
    }

    /// libghostty freed it (`kIOSurfacePurgeableEmpty`), or the system took back a volatile one: its pixels are
    /// gone.
    var emptied: Bool {
        var state = IOSurfacePurgeabilityState()
        setPurgeable(.purgeableKeepCurrent, oldState: &state)
        return state == .purgeableEmpty
    }
}
