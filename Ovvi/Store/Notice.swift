import Foundation

struct Notice {
    enum Tone {
        case error, warning, info, progress, success
    }

    /// One line: a toast or notice never wraps.
    let text: String
    /// The whole message, on hover, when `text` is the line of it that says what went wrong.
    var whole: String?
    var tone = Tone.error
    /// A terminal, not a pane: a pane id can name another pane after a move.
    var show: String?
    var retry: (@MainActor @Sendable () -> Void)?
    let id = UUID()

    /// The widest a toast or notice draws, so a long text stays one short line ending in …, not a band across the
    /// window or the card. It shows whole on hover.
    static let width: CGFloat = 520
}
