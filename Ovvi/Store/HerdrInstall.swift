import Foundation
import HerdrKit
import Observation

@MainActor @Observable
final class HerdrInstall {
    static let shared = HerdrInstall()

    enum Step: Equatable {
        case running(String)
        case failed(String)
    }

    private(set) var steps: [String: Step] = [:]

    /// `-herdrInstall` gives the e2e tests a fake installer, so no test installs herdr.
    static var command: String {
        UserDefaults.standard.string(forKey: "herdrInstall") ?? "curl -fsSL https://herdr.dev/install.sh | sh"
    }

    func install(on machine: Machine, session: String? = nil) async {
        if case .running = steps[machine.id] {
            return
        }
        steps[machine.id] = .running("")
        let exec = await machine.exec()
        var printed: [String] = []
        do {
            // A failed curl fails the pipe where the shell has pipefail; a `sh` without it exits on a bare `set`.
            let script = "(set -o pipefail) 2>/dev/null && set -o pipefail; exec 2>&1; " + Self.command
            let channel = try await exec.run(["sh", "-c", script])
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
                throw HerdrError.failed("No herdr on \(machine.name) after the install.")
            }
        } catch {
            steps[machine.id] = .failed((printed.suffix(6) + [error.localizedDescription]).joined(separator: "\n"))
            return
        }
        steps[machine.id] = .running("Connecting…")
        let stores = HostStore.all.filter { $0.machine.id == machine.id }
        if !machine.isRemote, let session {
            do {
                try await HostStore.start(session, on: machine)
            } catch {
                stores.first { $0.session == session }?.startProblem = error.localizedDescription
            }
        }
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
