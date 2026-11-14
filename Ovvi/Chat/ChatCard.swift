import HerdrKit
import SwiftUI

extension HostStore {
    func chat(_ pane: Pane) -> Chat? {
        guard let terminalID = pane.terminalID, let adapter = adapter(pane) else { return nil }
        if let chat = chats[terminalID], chat.adapter.token == adapter.token {
            // Only a change: Observation reports equal writes too, and every card body asks.
            if chat.paneID != pane.id {
                chat.paneID = pane.id
            }
            return chat
        }
        let launch = launches[terminalID].flatMap { $0.token == adapter.token ? $0 : nil }
        // A new conversation only from a launch that resumed nothing.
        let chat = Chat(adapter: adapter, paneID: pane.id, terminalID: terminalID, store: self,
                        current: launch?.fresh == true)
        chats[terminalID] = chat
        chat.showsChat = launch?.opensChat ?? views?[terminalID].map { $0 == "chat" }
            ?? (AppSettings().agentView == .chat)
        return chat
    }

    /// On the pane's machine, beside the cards' state files: it outlives the app, and a terminal's id survives moves.
    /// A cold restart of herdr gives new ids, but it also ends every chat (herdr starts the agents again without the
    /// flags). ponytail: two Macs on one remote session write the whole file, last writer wins; one file per pane if
    /// that shows.
    private var viewsPath: String {
        ".local/state/ovvi/\(session)/views.json"
    }

    /// After the first snapshot, so that terminals gone meanwhile go from the file.
    func loadViews() async {
        let text = await machine.exec().read(home: viewsPath)
        let saved = text.flatMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) } ?? [:]
        let live = Set(last?.panes.compactMap(\.terminalID) ?? [])
        var views = saved.filter { live.contains($0.key) }
        // Chats made ahead of the read.
        for chat in chats.values {
            if let view = views[chat.terminalID] {
                chat.showsChat = view == "chat"
            } else {
                views[chat.terminalID] = chat.showsChat ? "chat" : "tui"
            }
        }
        self.views = views
        if views != saved {
            writeViews()
        }
    }

    func keep(_ chat: Chat) {
        let view = chat.showsChat ? "chat" : "tui"
        guard views != nil, views?[chat.terminalID] != view else { return }
        views?[chat.terminalID] = view
        writeViews()
    }

    func writeViews() {
        guard let views, let data = try? JSONEncoder().encode(views) else { return }
        let previous = viewsWrite, path = viewsPath, machine = machine
        viewsWrite = Task {
            await previous?.value
            await machine.exec().write(home: path, String(decoding: data, as: UTF8.self))
        }
    }
}

extension Page {
    /// Chat is picked; it shows a loader until its history is current.
    func shownChat(_ pane: HostStore.Pane) -> Chat? {
        guard store.chooser(pane.id) == nil, !floats(pane), let chat = store.chat(pane),
              chat.showsChat else { return nil }
        return chat
    }

    /// A card showing its chat whose terminal the app keeps (D46): its tab's page stays made (`TabPages`). Only while
    /// the session answers, so that a kept chat follows nothing on a machine that is down. The terminals' bound is not
    /// observed: a page whose terminal the app let go goes at the next switch.
    func keepsChat(_ pane: HostStore.Pane) -> Bool {
        store.state == .live && !floats(pane)
            && pane.terminalID.map { store.chats[$0]?.showsChat == true && terminals.keeps($0) } == true
    }
}

extension View {
    /// The TUI of a chat that showed follows its agent as the chat does: a switch back to Chat then shows the rows at
    /// once, not a blank while the transcript is read again.
    func follows(_ chat: Chat?) -> some View {
        task(id: chat.map(ObjectIdentifier.init)) {
            if let chat, chat.shown {
                await chat.viewed()
            }
        }
    }
}

struct ChatSwitch: View {
    @Bindable var chat: Chat
    let page: Page

    var body: some View {
        let id = chat.paneID
        Segments(id: "pane.\(id).view", options: [("Chat", true), ("TUI", false)], selection: $chat.showsChat)
            .fixedSize()
            .onChange(of: chat.showsChat) {
                guard page.hasKeyboard(id) else { return }
                Task { page.terminals.focus(chat.terminalID) }
            }
    }
}

struct CardState: View {
    let chat: Chat?
    let state: AgentState?
    let paneID: String
    @Environment(\.look) private var look

    var body: some View {
        if let label {
            label.accessibilityIdentifier("pane.\(paneID).state")
        }
    }

    private var label: StateLabel? {
        guard let chat else { return state?.label(look) }
        // Only while the chat shows: the error is the chat view's, and a chat never shown follows nothing that would
        // clear it.
        if chat.problem != nil, chat.showsChat {
            return StateLabel(text: "Error", icon: .needsYou, color: look.error)
        }
        switch chat.phase {
        case .working: return AgentState.working.label(look)
        case .waiting: return AgentState.needsYou.label(look)
        // herdr's, as the TUI's header: pi idles at its prompt while it waits on agents or background jobs, which
        // herdr hears as working.
        case .ready, .starting: return state?.label(look)
        }
    }
}
