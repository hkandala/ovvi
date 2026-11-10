import HerdrKit
import OSLog

extension HostStore {
    private static let log = Logger(ovvi: "agent")

    /// Several Ovvis can follow a session: one whose user is away lets the one in use take the request first.
    func answer(request id: String, from pane: String) async {
        if away {
            try? await Task.sleep(for: .milliseconds(500))
        }
        let exec = await machine.exec()
        guard let data = try? await exec.take(request: id) else { return }
        let answer: AgentAnswer
        do {
            let request = try AgentRequest(data)
            answer = await AgentCommands.run(request.argv, cwd: request.cwd, from: pane, request: id, store: self)
        } catch let .newer(version) {
            answer = AgentCommands.failure(AgentError(code: "protocol", message: """
            the request speaks protocol \(version); this Ovvi speaks \(AgentRequest.version)
            """), json: false)
        } catch {
            let why = "not a request of protocol \(AgentRequest.version), or over 64 KiB or 64 fields"
            answer = AgentCommands.failure(AgentError.usage(why), json: false)
        }
        do {
            try await exec.answer(request: id, code: answer.code, out: answer.out, err: answer.err)
        } catch {
            Self.log.error("answer to \(id) failed: \(error.localizedDescription)")
        }
    }
}
