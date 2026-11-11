import HerdrKit
import SwiftUI

struct EnableChat: View {
    let pane: HostStore.Pane
    let page: Page
    @State private var asking = false
    @Environment(\.look) private var look

    static func offered(_ pane: HostStore.Pane, _ store: HostStore) -> Bool {
        guard pane.program != nil, store.adapter(pane) == nil, let session = pane.session,
              let adapter = Chooser.agent(pane.agent)?.adapter else { return false }
        return adapter.resume(session) != nil && store.chooser(pane.id) == nil
    }

    var body: some View {
        let name = pane.agentLabel ?? "the agent"
        Button {
            if pane.state == .working || pane.state == .needsYou {
                asking = true
            } else {
                page.store.enableChat(pane)
            }
        } label: {
            Label("Relaunch with Chat", systemImage: "bubble.left.and.text.bubble.right")
                .font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).frame(height: 20)
        }
        .buttonStyle(ChromeStyle(radius: 6))
        .padding(2)
        .background(look.track, in: .rect(cornerRadius: 8))
        .fixedSize()
        .help("Restart \(name) with chat, in the same session")
        .accessibilityIdentifier("pane.\(pane.id).enable-chat")
        .alert("Restart \(name)?", isPresented: $asking) {
            Button("Restart", role: .destructive) { page.store.enableChat(pane) }
            Button("Cancel", role: .cancel) {}
        } message: {
            let doing = pane.state == .needsYou ? "waiting for you" : "working"
            Text("\(name) is \(doing). It stops, then starts again in the same session, with chat.")
        }
    }
}

/// An agent's header control, the same in a card and in a floating pane's title row: the Chat | TUI switch, else
/// Relaunch with Chat.
struct AgentControl: View {
    let pane: HostStore.Pane
    let chat: Chat?
    let page: Page

    var body: some View {
        if let chat {
            ChatSwitch(chat: chat, page: page)
        } else if EnableChat.offered(pane, page.store) {
            EnableChat(pane: pane, page: page)
        }
    }
}
