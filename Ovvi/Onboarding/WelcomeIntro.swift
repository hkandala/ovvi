import AppKit
import SwiftUI

/// The welcome's first two seconds: the app's icon fades and scales in, a soft light sweeps once across it, and the
/// name fades in under it; then `done`, and the panel dissolves into its first page. Reduce Motion: a plain fade.
struct WelcomeIntro: View {
    let reduceMotion: Bool
    let done: () -> Void
    @State private var shown = false
    /// The light's place along the icon's diagonal, from before its top left (-1) to past its bottom right (1).
    @State private var sweep: CGFloat = -1
    @State private var named = false

    var body: some View {
        let icon = Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
            .frame(width: 132, height: 132)
        VStack(spacing: 14) {
            icon
                .overlay {
                    // A white light (onAccent's white) on the tile in both looks.
                    LinearGradient(stops: [.init(color: .clear, location: 0.38),
                                           .init(color: Look.onAccent.opacity(0.55), location: 0.5),
                                           .init(color: .clear, location: 0.62)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: 264, height: 264)
                        .offset(x: sweep * 132, y: sweep * 132)
                        .blendMode(.plusLighter)
                        .mask(icon)
                        .opacity(reduceMotion ? 0 : 1)
                }
                .scaleEffect(shown || reduceMotion ? 1 : 0.86)
                .opacity(shown ? 1 : 0)
            Text("Ovvi").font(.system(size: 30, weight: .semibold)).kerning(0.3)
                .opacity(named ? 1 : 0)
                .offset(y: named || reduceMotion ? 0 : 8)
                .blur(radius: named || reduceMotion ? 0 : 6)
        }
        .padding(.bottom, 24)
        .task {
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.5)) { (shown, named) = (true, true) }
                try? await Task.sleep(for: .seconds(1.6))
            } else {
                withAnimation(.spring(duration: 0.6, bounce: 0.2)) { shown = true }
                try? await Task.sleep(for: .seconds(0.3))
                withAnimation(.easeInOut(duration: 0.95)) { sweep = 1 }
                try? await Task.sleep(for: .seconds(0.4))
                withAnimation(.easeOut(duration: 0.6)) { named = true }
                try? await Task.sleep(for: .seconds(1.0))
            }
            if !Task.isCancelled {
                done()
            }
        }
    }
}
