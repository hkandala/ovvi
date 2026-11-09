import Foundation
import HerdrKit

extension HostStore {
    /// One `pane.process_info`; the icon follows. Only the latest ask lands; a failed first one is made again.
    /// `soon`: the user waits on it (a card shows, Return in it): ahead of the first snapshot's asks.
    func askProgram(_ paneID: String, soon: Bool = false) async {
        guard let client, let pane = pane(paneID), !pane.starting else { return }
        pane.asked = true
        pane.asks += 1
        let ask = pane.asks
        await asks.enter(first: soon)
        defer { asks.leave() }
        // A newer ask, a closed pane or a closed page while it waited: no herdr run.
        guard ask == pane.asks, self.client != nil, self.pane(paneID) === pane else { return }
        do {
            let program = try await client.program(paneID)
            Latency.shared.step("program")
            if ask == pane.asks {
                bind(pane, program, ask: ask)
                pane.program = program
                keepPlaceholder(pane)
            }
        } catch {
            if ask == pane.asks, pane.program == nil {
                pane.asked = false
            }
        }
    }

    /// Asks what the pane runs: when it is new (or a new terminal under a reused id), and when its agent or title word
    /// changes. A progress title ("build 51%") changes on and on; its first word does not.
    func watchProgram(_ pane: Pane, _ new: HerdrKit.Pane) {
        watchTitle(pane, new)
        if new.terminalID != pane.terminalID {
            restore(new)
            pane.program = nil
            pane.asked = false
            pane.asks += 1 // the old terminal's answer in flight
            pane.drawnLabel = new.label
        }
        let word = { (title: String?) in title?.split(separator: " ").first }
        // A new label too: a pane labeled a card by hand gets its placeholder (`keepPlaceholder`).
        if pane.asked,
           new.agent != pane.agent || word(new.title) != word(pane.terminalTitle) || new.label != pane.label
        {
            Task { await askProgram(pane.id) }
        }
        // Every pane once, for its tab's icons and the hover card, also in tabs never shown; a failed ask is made
        // again. A new pane a second later, as after Return, and no other ask before (its card's as it shows): a new
        // shell's startup runs short-lived programs. The first snapshot's at once: their shells started long ago.
        if !pane.asked {
            pane.asked = true
            pane.starting = state == .live
            Task {
                if pane.starting {
                    try? await Task.sleep(for: .seconds(1))
                    // A slow startup (a cold nvm) runs on: then until only the shell runs, 3 s more at most.
                    // ponytail: one sample of the shell alone can fall between two startup programs; require two in
                    // a row if a guess still shows.
                    var tries = 0
                    var program = try? await client?.program(pane.id)
                    while tries < 6, program?.isShell == false {
                        tries += 1
                        try? await Task.sleep(for: .milliseconds(500))
                        program = try? await client?.program(pane.id)
                    }
                    // Its last answer, before it stops starting: a tab title shows "New Tab" until then.
                    pane.program = program ?? pane.program
                    pane.starting = false
                    keepPlaceholder(pane)
                    if program != nil {
                        return
                    }
                }
                await askProgram(pane.id)
            }
        }
    }
}

extension HostStore {
    /// Reads its agent's session title again (`Exec.sessionTitle`) when the session, the terminal title or the status
    /// changes: agents name a session during a turn, and pi's `/name` retitles its terminal. Through the program asks'
    /// gate: a session's first snapshot has every agent at once.
    func watchTitle(_ pane: Pane, _ new: HerdrKit.Pane) {
        let session = new.agentSession.flatMap { $0.agent == new.agent ? $0.value : nil }
        if pane.session != session {
            pane.session = session
        }
        let key = session.map { "\($0) \(new.title ?? "") \(new.agentStatus?.rawValue ?? "")" }
        guard key != pane.titleKey else { return }
        pane.titleKey = key
        guard let session, let agent = new.agent else {
            pane.sessionTitle = nil
            return
        }
        Task {
            await asks.enter()
            defer { asks.leave() }
            guard pane.titleKey == key else { return }
            let title = await machine.exec().sessionTitle(agent: agent, session: session, home: ArchivedShelf.home)
            if pane.titleKey == key, pane.sessionTitle != title {
                pane.sessionTitle = title
            }
        }
    }
}
