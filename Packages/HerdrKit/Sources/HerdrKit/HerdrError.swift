import Foundation

public enum HerdrError: Error, Equatable, Sendable {
    case notFound
    case unsupported(String)
    case timeout
    case herdr(code: String, message: String)
    case failed(String)
    /// ssh needs an answer the user gives; only Connect tries again.
    case disconnected(String)
    case refused(String)

    public var isMachineProblem: Bool {
        switch self {
        case .notFound, .unsupported, .disconnected: true
        default: false
        }
    }
}

extension HerdrError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound: "herdr is not installed"
        case let .unsupported(message), let .failed(message), let .disconnected(message): message
        case .timeout: "herdr did not answer"
        case let .herdr(code, message): "\(message) (\(code))"
        case .refused("zoomed_tab"): "The tab is zoomed in herdr"
        case let .refused(reason): "herdr changed nothing (\(reason))"
        }
    }
}
