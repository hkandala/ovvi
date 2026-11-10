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
}
