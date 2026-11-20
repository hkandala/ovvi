import SwiftUI

/// Settings ▸ General ▸ Rebuild in Ovvi Dev: `make install` bakes in the repo it built from (`OvviRepo`), empty in
/// every other build; UI tests pass `-OvviRepo`. The repo's `scripts/rebuild.swift` shows make install's log, runs it
/// once this app quit, then opens the new build.
struct RebuildRow: View {
    static let repo = UserDefaults.standard.string(forKey: "OvviRepo")
        ?? Bundle.main.object(forInfoDictionaryKey: "OvviRepo") as? String ?? ""

    @State private var starting = false
    @State private var problem: String?
    @Environment(\.look) private var look

    var body: some View {
        LabeledContent {
            Button("Rebuild") { start() }.disabled(starting).accessibilityIdentifier("settings.general.rebuild")
        } label: {
            Text("Rebuild from source")
            if let problem {
                Text(problem).foregroundStyle(look.error).accessibilityIdentifier("settings.general.rebuild.problem")
            } else {
                Text("Runs make install in \(Self.repo), then opens the new build.")
            }
        }
    }

    /// The script prints a line once its window shows; this app quits then, so make install can replace it.
    private func start() {
        starting = true
        problem = nil
        let script = Process(), shown = Pipe()
        script.executableURL = URL(filePath: "/usr/bin/swift")
        script.arguments = [Self.repo + "/scripts/rebuild.swift", String(getpid()), Bundle.main.bundlePath]
        script.currentDirectoryURL = URL(filePath: Self.repo)
        script.standardOutput = shown
        shown.fileHandleForReading.readabilityHandler = { handle in
            handle.readabilityHandler = nil
            if handle.availableData.isEmpty {
                Task { @MainActor in failed("The rebuild did not start.") }
            } else {
                // A block of the run loop, not of the main queue: the quit waits for HostStore.unmarkAll on the main
                // queue.
                RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            }
        }
        do {
            try script.run()
        } catch {
            failed(error.localizedDescription)
        }
    }

    private func failed(_ text: String) {
        problem = text
        starting = false
    }
}
