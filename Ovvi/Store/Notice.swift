import Foundation

struct Notice {
    enum Tone {
        case error, warning, info, progress, success
    }

    let text: String
    var tone = Tone.error
    /// A terminal, not a pane: a pane id can name another pane after a move.
    var show: String?
    var retry: (@MainActor @Sendable () -> Void)?
    let id = UUID()

    /// The widest a toast or notice draws, so a long error stays a short line ending in …, not a band across the window
    /// or the card. It shows whole on hover.
    static let width: CGFloat = 520
}
