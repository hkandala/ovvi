import AppKit
import SwiftUI

/// Every motion the app runs reads one of these (`make lint`'s `animations` rule): with Settings ▸ Appearance ▸
/// Animations off, each one takes no time.
extension Animation {
    /// CI's Mac has Reduce Motion on.
    private static let forceMotion = UserDefaults.standard.bool(forKey: "forceMotion")

    /// Settings ▸ Appearance ▸ Animations off (`AppSettings.animations`).
    static var off: Bool {
        // A launch argument (`-animations NO`) is a string: `bool(forKey:)` reads both.
        UserDefaults.standard.object(forKey: "animations") != nil && !UserDefaults.standard.bool(forKey: "animations")
    }

    /// The system's Reduce Motion alone.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !forceMotion
    }

    /// No movement: Reduce Motion or Animations off.
    static var reduced: Bool {
        off || reduceMotion
    }

    /// A motion that Reduce Motion keeps (a fade, a highlight), none with Animations off.
    static func motion(_ animation: Animation) -> Animation? {
        off ? nil : animation
    }

    static var highlight: Animation? {
        .motion(.easeOut(duration: 0.12))
    }

    static var slide: Animation? {
        reduced ? nil : .timingCurve(.slide, duration: 0.22)
    }

    static var fade: Animation? {
        reduced ? nil : .easeOut(duration: 0.2)
    }
}

extension UnitCurve {
    /// Rex's "production" curve.
    static let slide = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.9),
                                        endControlPoint: UnitPoint(x: 0.3, y: 1))
}
