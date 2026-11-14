import Foundation
import HerdrKit
import Observation

@MainActor @Observable
final class Chat {
    enum Phase: Equatable {
        case starting, ready, working, waiting
    }

    struct Outgoing: Identifiable, Equatable {
        static let dimmed = 0.7
        let id = UUID()
        let text: String
        var notSent = false
    }

    let adapter: any ChatAdapter
    var paneID: String
    let terminalID: String
    @ObservationIgnored weak var store: HostStore?
    var history = ChatHistory() {
        // Not `oldValue`: reading it copies the whole history at every line.
        didSet { confirm() }
    }

    @ObservationIgnored private var seen = 0

    var showsChat = false {
        didSet { store?.keep(self) }
    }

    /// The history holds what the agent wrote: the chat shows a loader until then, its empty state only once it knows
    /// the conversation is new. False for a chat found running or resumed until its transcript is read, and for one
    /// nothing followed for a while.
    var current: Bool
    var recorded: Phase?
    var question: ChatQuestion?
    var problem: String?
    var outgoing: [Outgoing] = []
    var draft = ""
    var wantsKeyboard = false
    @ObservationIgnored var marks: [String: FileMark] = [:]
    @ObservationIgnored var backlog = ChatHistory()
    @ObservationIgnored var loading = false
    /// Lines read off the main actor: changes wait in `queued` until they are in.
    @ObservationIgnored var reading = false
    @ObservationIgnored var queued: [(source: String?, body: (inout ChatHistory) -> Void)] = []
    @ObservationIgnored var source: String?
    @ObservationIgnored private var viewers = 0
    /// A card showed the chat: its TUI follows the agent too, so that a switch back shows the rows at once.
    @ObservationIgnored private(set) var shown = false
    @ObservationIgnored private var following: Task<Void, Never>?
    @ObservationIgnored private var starting: Task<Void, Never>?

    init(adapter: any ChatAdapter, paneID: String, terminalID: String, store: HostStore, current: Bool) {
        self.adapter = adapter
        self.current = current
        self.paneID = paneID
        self.terminalID = terminalID
        self.store = store
    }

    var phase: Phase {
        if let recorded {
            return recorded
        }
        switch store?.pane(paneID)?.state {
        case .needsYou: return .waiting
        case .working: return .working
        case .idle, .finishedUnseen: return .ready
        case nil: return .starting
        }
    }

    var live: Bool {
        store?.pane(paneID).flatMap { store?.adapter($0) }?.token == adapter.token
    }

    var drawer: Bool {
        phase == .waiting && question == nil
    }

    func viewed() async {
        shown = true
        viewers += 1
        if viewers == 1, let store {
            let old = following
            following = Task {
                // A card gone and back at once: the last follow ends first, so two never read from one mark.
                await old?.value
                let exec = await store.machine.exec()
                while !Task.isCancelled {
                    await adapter.follow(self, on: exec)
                    try? await Task.sleep(for: .seconds(2))
                }
                // Reset once the adapter returns, so that none of its tasks writes after.
                if viewers == 0 {
                    recorded = nil
                    current = current && history.entries.isEmpty
                }
            }
        }
        defer {
            viewers -= 1
            if viewers == 0 {
                following?.cancel()
            }
        }
        // Until the card goes.
        while await (try? Task.sleep(for: .seconds(3600))) != nil {}
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client = store?.client else { return }
        if text.hasPrefix("/") {
            showsChat = false
            draft = ""
            Task { try? await client.sendInput(text, keys: [], pane: paneID) }
            return
        }
        // A dialog takes no message: its answers go first.
        guard phase != .waiting else { return }
        let message = Outgoing(text: text)
        outgoing.removeAll(where: \.notSent)
        outgoing.append(message)
        draft = ""
        // Typed while the agent starts (pi's session is read from its machine), it waits, dimmed, as one on its way
        // does, and goes once the agent is ready, at most 30 s. One wait after another: messages go in their order.
        let previous = starting
        let ready = Task {
            await previous?.value
            for _ in 0 ..< 150 where phase == .starting {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        starting = ready
        Task {
            await ready.value
            // Not to an agent started again in the pane: that one has a chat of its own.
            guard live, phase == .ready || phase == .working else { return notSent(message.id) }
            let sent = await (try? client.prompt(text, pane: paneID)) != nil
            if !sent {
                notSent(message.id)
                return
            }
            // Claude Code's company hooks can take a few seconds to log a prompt; pi logs one sent while it works
            // when it takes it, after the running tool (or its dialog).
            try? await Task.sleep(for: .seconds(5))
            while phase == .working || phase == .waiting {
                try? await Task.sleep(for: .seconds(1))
            }
            notSent(message.id)
        }
    }

    private func notSent(_ id: UUID) {
        guard let index = outgoing.firstIndex(where: { $0.id == id && !$0.notSent }) else { return }
        outgoing[index].notSent = true
        if draft.isEmpty {
            draft = outgoing[index].text
        }
    }

    /// All the new entries, not only the last: a burst brings the user's message with the reply after it.
    private func confirm() {
        let (old, count) = (seen, history.entries.count)
        seen = count
        guard !outgoing.isEmpty else { return }
        // The same count: only the last entry changed in place (an earlier same text is an earlier message).
        for entry in history.entries.dropFirst(count > old ? old : count == old ? max(count - 1, 0) : 0) {
            guard case let .user(text) = entry.kind else { continue }
            let sent = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = outgoing.firstIndex(where: { $0.text == sent }),
               // Confirmed after "Not sent": the draft it gave back would send it twice.
               outgoing.remove(at: index).notSent, draft == sent
            {
                draft = ""
            }
        }
    }

    func stop() {
        guard phase == .working, let client = store?.client else { return }
        let keys = type(of: adapter).stopKeys, paneID = paneID
        Task { try? await client.sendKeys(keys, pane: paneID) }
    }

    func answer(_ answers: [String: String]) {
        guard let question, !question.answered, let store else { return }
        self.question?.answered = true
        Task {
            if await !adapter.answer(question, answers, on: store.machine.exec()), self.question?.raw == question.raw {
                self.question = nil
            }
        }
    }
}

struct ChatQuestion: Equatable {
    struct Item: Equatable {
        let text: String
        let options: [String]
    }

    let items: [Item]
    let raw: Data
    var answered = false
}

extension ChatQuestion {
    /// Claude Code's and OpenCode's questions (`question`, `options[].label`); nil when one takes several answers
    /// (`several` is the agent's key for it) or has no options: the live terminal answers those.
    static func items(_ questions: [[String: Any]], several: String) -> [Item]? {
        let items = questions.map { question in
            Item(text: question["question"] as? String ?? "",
                 options: (question["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String })
        }
        guard !items.isEmpty, !questions.contains(where: { $0[several] as? Bool == true }),
              items.allSatisfy({ !$0.options.isEmpty }) else { return nil }
        return items
    }
}
