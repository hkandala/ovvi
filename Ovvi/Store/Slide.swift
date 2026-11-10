import SwiftUI

extension HostStore {
    /// 0.2 s felt slow.
    static let slide = 0.13

    func slide() {
        redraw()
        if !Animation.reduced {
            sliding = .now + .seconds(Self.slide)
        }
    }

    /// herdr's answer comes during a split's slide, and its apply and the views it changes (the new pane's card and
    /// terminal, the menus) take 30–60 ms of the main thread: frames the slide loses.
    func slid() async {
        while sliding > .now, !Task.isCancelled {
            try? await Task.sleep(until: sliding)
        }
    }
}
