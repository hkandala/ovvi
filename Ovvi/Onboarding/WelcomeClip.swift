import AVFoundation
import SwiftUI

/// A welcome page's picture: a short silent clip of the app (Ovvi/Onboarding/Clips, made by
/// scripts/welcome-clips.sh), looped from its start each time the page shows, with no controls. Reduce Motion: its
/// first frame, still.
struct WelcomeClip: NSViewRepresentable {
    let player: AVQueuePlayer?

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    /// The app's look changed while the page shows: the other look's clip.
    func updateNSView(_ view: NSView, context _: Context) {
        if let layer = view.layer as? AVPlayerLayer, layer.player !== player {
            layer.player = player
        }
    }

    /// Every page's player, made once when the panel opens, so a page's first frame is ready before it shows.
    @MainActor
    final class Reels {
        private var reels: [String: (AVQueuePlayer, AVPlayerLooper)] = [:]

        func player(_ name: String) -> AVQueuePlayer? {
            if let reel = reels[name] {
                return reel.0
            }
            guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else { return nil }
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            reels[name] = (player, AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url)))
            return player
        }

        /// Plays `name` from its start, or shows its frame at `still` seconds (Reduce Motion); stops the others.
        func show(_ name: String?, at still: Double?) {
            for (key, reel) in reels where key != name {
                reel.0.pause()
            }
            guard let name, let player = player(name) else { return }
            player.seek(to: CMTime(seconds: still ?? 0, preferredTimescale: 600), toleranceBefore: .zero,
                        toleranceAfter: .zero)
            if still == nil {
                player.play()
            }
        }
    }
}
