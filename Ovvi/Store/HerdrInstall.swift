import Foundation
import HerdrKit
import Observation

/// Installs herdr on a machine with the command from herdr's docs, on This Mac or over the machine's SSH connection,
/// then connects the machine's pages (ui/states). A missing or too old herdr's page shows its button.
@MainActor @Observable
final class HerdrInstall {
    static let shared = HerdrInstall()

    enum Step: Equatable {
        /// The installer's last line, or what comes after it.
        case running(String)
        /// The end of what the installer printed.
        case failed(String)
    }

    /// By machine id.
    private(set) var steps: [String: Step] = [:]

    /// herdr.dev's install command; `-herdrInstall` gives the e2e tests a fake installer, so no test installs herdr.
    static var command: String {
        UserDefaults.standard.string(forKey: "herdrInstall") ?? "curl -fsSL https://herdr.dev/install.sh | sh"
    }

    /// Runs the installer, then starts the page's session on This Mac (as a new window's first page does) and reads
    /// every page of the machine again.
    func install(on machine: Machine, session: String) async {
        if case .running = steps[machine.id] {
            return
        }
        steps[machine.id] = .running("")
        let exec = await machine.exec()
        var printed: [String] = []
        do {
            // Its errors go to stderr: one stream, in order, for the failure's text.
            let channel = try await exec.run(["sh", "-c", Self.command + " 2>&1"])
            channel.closeInput()
            for await line in channel.lines {
                let text = line.replacing(/\u{1B}\[[0-9;]*m/, with: "").trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    printed.append(text)
                    steps[machine.id] = .running(text)
                }
            }
            let (status, _) = await channel.exit()
            guard status == 0 else { throw HerdrError.failed("The installer exited with status \(status).") }
            await exec.forgetHerdr()
            guard try await exec.herdr() != nil else {
                throw HerdrError.failed("herdr is installed, but the login shell on \(machine.name) does not find it.")
            }
        } catch {
            steps[machine.id] = .failed((printed.suffix(6) + [error.localizedDescription]).joined(separator: "\n"))
            return
        }
        steps[machine.id] = .running("Connecting…")
        if !machine.isRemote {
            try? await HostStore.start(session, on: machine)
        }
        let stores = HostStore.all.filter { $0.machine.id == machine.id }
        for store in stores {
            await store.client?.refresh()
        }
        // Until the pages leave "not installed", so it never shows again between the install and their read.
        for _ in 0 ..< 100 where stores.contains(where: { $0.state == .failed(.notFound) }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        steps[machine.id] = nil
    }
}
