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
        let chat = Chat(adapter: adapter, paneID: pane.id, terminalID: terminalID, store: self)
        chat.showsChat = launches[terminalID].map { $0.opensChat && $0.token == adapter.token } == true
        chats[terminalID] = chat
        return chat
    }
}

extension Page {
    func shownChat(_ pane: HostStore.Pane) -> Chat? {
        pickedChat(pane).flatMap { $0.current ? $0 : nil }
    }

    /// Chat is picked: the card shows it once its history is current (`Chat.catchUp`).
    func pickedChat(_ pane: HostStore.Pane) -> Chat? {
        guard store.chooser(pane.id) == nil, !floats(pane), let chat = store.chat(pane),
              chat.showsChat else { return nil }
        return chat
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
        // Only while the chat shows: nothing follows the agent behind its terminal, so nothing would clear it.
        if chat.problem != nil, chat.showsChat {
            return StateLabel(text: "Error", icon: .needsYou, color: look.error)
        }
        switch chat.phase {
        case .working: return AgentState.working.label(look)
        case .waiting: return AgentState.needsYou.label(look)
        case .ready, .starting: return state == .finishedUnseen ? AgentState.finishedUnseen.label(look) : nil
        }
    }
}
