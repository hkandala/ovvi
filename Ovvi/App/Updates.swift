import Sparkle
import SwiftUI

/// Sparkle's updater (D112). A daily check that finds an update shows the window's update notice, not Sparkle's window
/// (gentle reminders); Update… opens Sparkle's.
@MainActor @Observable
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updates()
    /// Only builds with a feed check: the installed app and Ovvi Tip (`make install`, `make zip`), not Debug builds,
    /// the UI tests or the measures' `make app`.
    static let checks = !((Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "").isEmpty

    /// Ovvi ▸ Check for Updates…, in the palette too.
    static var commands: [Command] {
        guard checks else { return [] }
        return [Command(section: .app, title: "Check for Updates…", symbol: "arrow.down.circle",
                        keywords: "update version release new") { shared.check() }]
    }

    /// The version the notice offers; nil hides it.
    var available: String?
    @ObservationIgnored private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self,
    )

    func start() {
        if Self.checks {
            controller.startUpdater()
        }
    }

    /// Check for Updates…, and the notice's Update…, which brings the update it found forward.
    func check() {
        available = nil
        controller.checkForUpdates(nil)
    }

    /// Settings ▸ General ▸ Check for updates automatically; Sparkle keeps it in the app's defaults.
    var automatic: Bool {
        get {
            access(keyPath: \.automatic)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automatic) { controller.updater.automaticallyChecksForUpdates = newValue }
        }
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem, andInImmediateFocus _: Bool,
    ) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state _: SPUUserUpdateState,
    ) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            available = handleShowingUpdate ? nil : version
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { available = nil }
    }
}

/// Under the window's other notices, until Update… or Close (Window ▸ Notice).
struct UpdateNotice: View {
    var body: some View {
        if let version = Updates.shared.available {
            NoticeCapsule(tone: .info, text: "Ovvi \(version) is available", symbol: "arrow.down.circle.fill") {
                Button("Update…") { Updates.shared.check() }.accessibilityIdentifier("notice.update.update")
                Button("Close", systemImage: "xmark") { Updates.shared.available = nil }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityIdentifier("notice.update.close")
            }
            .accessibilityIdentifier("notice.update")
        }
    }
}
