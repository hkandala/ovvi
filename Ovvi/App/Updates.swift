import Sparkle
import SwiftUI

/// Sparkle's updater (D112). A daily check that finds an update shows the window's update notice, not Sparkle's window
/// (gentle reminders); Update… opens Sparkle's.
@MainActor @Observable
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updates()
    /// Only the released app has a feed (`make zip`): not Ovvi Dev (`make install`), Debug builds or the measures'
    /// `make app`. Sparkle reads a feed in the defaults first, so a UI test that passes `-SUFeedURL` gets the Updates
    /// settings.
    static let checks = !(UserDefaults.standard.string(forKey: "SUFeedURL")
        ?? Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "").isEmpty

    /// Ovvi ▸ Check for Updates…, in the palette too.
    static var commands: [Command] {
        guard checks else { return [] }
        return [Command(section: .app, title: "Check for Updates…", symbol: "arrow.down.circle",
                        keywords: "update version release new") { shared.check() }]
    }

    /// The version the notice offers; nil hides it.
    var available: String?
    /// Sparkle's `canCheckForUpdates`: false before it starts and while a check runs (Settings' Check Now).
    private(set) var canCheck = false
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self,
    )

    func start() {
        guard Self.checks else { return }
        controller.startUpdater()
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: .initial) { _, _ in
            MainActor.assumeIsolated { Updates.shared.canCheck = Updates.shared.controller.updater.canCheckForUpdates }
        }
    }

    /// Check for Updates…, Settings' Check Now, and the notice's Update…, which brings the update it found forward.
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
