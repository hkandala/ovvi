import AppKit
import SwiftUI

struct WindowBackground: View {
    let look: Look

    var body: some View {
        if look.style == .glass {
            Frosted().overlay(look.backdrop.blendMode(BlendMode.overlay)).overlay(look.window)
        } else {
            look.window
        }
    }
}

/// SwiftUI's materials blur only what is inside the window.
private struct Frosted: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        // AppKit's default drops the blur in an inactive window.
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}
