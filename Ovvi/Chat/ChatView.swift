import HerdrKit
import SwiftUI

struct ChatView: View {
    @Bindable var chat: Chat
    let page: Page
    let terminal: PaneTerminal?
    static let column: CGFloat = 760
    static let gutter: CGFloat = 48
    @State private var height: CGFloat = 0
    @FocusState private var composing: Bool
    @Environment(\.pageHidden) private var hidden

    var body: some View {
        VStack(spacing: 0) {
            ChatMessages(chat: chat, page: page, floats: page.store.pane(chat.paneID).map(page.floats) == true,
                         composing: $composing).equatable()
            if chat.drawer, let terminal {
                WaitingDrawer(chat: chat, page: page, terminal: terminal).frame(height: max(160, height * 0.45))
                    .padding(.bottom, 14).padding(.top, 4).readingColumn()
            }
        }
        .onExitCommand(perform: chat.stop)
        // Not a double or triple click or a ⇧-click, which select text (Copy needs it to stay), nor a ⌃-click, which
        // opens the menu.
        .contentShape(.rect)
        .simultaneousGesture(TapGesture().onEnded {
            guard let event = NSApp.currentEvent, event.clickCount < 2,
                  event.modifierFlags.isDisjoint(with: [.shift, .control]) else { return }
            if !chat.drawer {
                composing = true
            } else {
                page.terminals.focus(chat.terminalID)
            }
        })
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .task(id: ObjectIdentifier(chat)) { await chat.viewed() }
        .onChange(of: chat.phase) { old, new in
            if old == .waiting, new != .waiting {
                chat.question = nil
            }
        }
        .onAppear {
            if page.hasKeyboard(chat.paneID) {
                chat.wantsKeyboard = true
            }
        }
        .blursWhenHidden($composing)
        .onChange(of: [chat.wantsKeyboard, hidden], initial: true) {
            // On the next turn: a first responder set during an update is undone.
            if chat.wantsKeyboard, !hidden {
                chat.wantsKeyboard = false
                Task { composing = true }
            }
        }
        .onChange(of: composing) {
            if composing {
                page.tookKeyboard(chat.terminalID)
            }
        }
    }
}

extension View {
    func readingColumn(margin: CGFloat = 32) -> some View {
        padding(.horizontal, margin).frame(maxWidth: ChatView.column).frame(maxWidth: .infinity)
    }
}

/// Its own view, so that a key typed in it changes nothing else.
struct Composer: View {
    @Bindable var chat: Chat
    var composing: FocusState<Bool>.Binding
    static let inset: CGFloat = 18

    var body: some View {
        let working = chat.phase == .working
        return VStack(alignment: .leading, spacing: 2) {
            TextField("Ask Anything", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1 ... 5)
                .focused(composing)
                .onSubmit { chat.send(chat.draft) }
                .onKeyPress(.return, phases: [.down, .repeat]) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                    return .handled
                }
                .padding(.trailing, Self.inset - 11)
                .accessibilityIdentifier("chat.\(chat.paneID).composer")
            HStack(spacing: 8) {
                let model = [chat.history.model.map(ChatHistory.modelName), chat.history.effort].compactMap(\.self)
                    .joined(separator: " · ")
                if !model.isEmpty {
                    Text(model).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityIdentifier("chat.\(chat.paneID).model")
                }
                Spacer(minLength: 0)
                if working, chat.draft.isEmpty {
                    roundButton("stop.fill", help: "Stop", id: "chat.\(chat.paneID).stop", action: chat.stop)
                } else {
                    roundButton("arrow.up", help: "Send", id: "chat.\(chat.paneID).send") { chat.send(chat.draft) }
                }
            }
        }
        .padding(.leading, Self.inset).padding(.trailing, 11).padding(.top, 13).padding(.bottom, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .contentShape(.rect)
        .onTapGesture { composing.wrappedValue = true }
    }

    private func roundButton(_ symbol: String, help: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Look.onAccent)
                .frame(width: 22, height: 22)
                .background(.tint, in: .circle)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(id)
    }
}

private struct WaitingDrawer: View {
    let chat: Chat
    let page: Page
    let terminal: PaneTerminal
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(look.needsYou).frame(width: 7, height: 7)
                Text("\(chat.adapter.name) is asking in the terminal").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                Button("Open TUI") { chat.showsChat = false }.buttonStyle(.glass).controlSize(.small)
                    .accessibilityIdentifier("chat.\(chat.paneID).open-terminal")
            }
            TerminalCard(terminal: terminal, watched: page.watched, alpha: 1)
                .clipShape(.rect(cornerRadius: 6))
        }
        .padding(8)
        .background(look.needsYou.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(look.needsYou.opacity(0.35)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.\(chat.paneID).drawer")
        .onAppear {
            if page.hasKeyboard(chat.paneID) {
                page.terminals.focus(chat.terminalID)
            }
        }
        .onDisappear {
            if page.hasKeyboard(chat.paneID) {
                chat.wantsKeyboard = true
            }
        }
    }
}

extension ChatMessages {
    /// As in the terminal, with a plain click too: chat text is no program's, so a click opens as a browser's link
    /// does, in a new tab, selected.
    func openLink(_ url: URL) -> OpenURLAction.Result {
        guard let link = ChatLinks.link(url) else { return .discarded }
        Links.open(link, how: PaneSurfaceView.linkKey(NSEvent.modifierFlags) ?? .here, from: chat.terminalID,
                   page: page)
        return .handled
    }
}
