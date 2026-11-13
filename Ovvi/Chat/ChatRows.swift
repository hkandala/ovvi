import HerdrKit
import SwiftUI

struct ChatRowView: View, Equatable {
    let row: ChatRow
    let paneID: String
    let counts: String
    let steps: [ChatEntry]?
    let toggle: () -> Void
    let opened: Set<String>
    let toggleTool: (String) -> Void
    @Environment(\.look) private var look

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        // Only an open run reads `opened`.
        lhs.row == rhs.row && lhs.counts == rhs.counts && lhs.steps == rhs.steps && lhs.paneID == rhs.paneID
            && (lhs.steps == nil || lhs.opened == rhs.opened)
    }

    var body: some View {
        switch row {
        case let .user(_, text): UserBubble(text: text, paneID: paneID).padding(.vertical, 8)
        case .stack:
            ToolStack(counts: counts, steps: steps, paneID: paneID, toggle: toggle, opened: opened,
                      toggleTool: toggleTool)
        case let .worked(_, seconds):
            let text = "Worked " + ChatHistory.duration(seconds)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                .readableText(text)
                .accessibilityIdentifier("chat.\(paneID).worked")
        case let .reply(_, text):
            Markdown(text: text).accessibilityIdentifier("chat.\(paneID).reply")
                .bubble(look.receivedBubble).replyPlace(Bubble.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .todos(_, todos): Plan(todos: todos)
        case let .note(_, text, failed):
            Label(text, systemImage: failed ? "exclamationmark.triangle.fill" : "stop.circle")
                .font(.system(size: 12)).foregroundStyle(failed ? AnyShapeStyle(look.error) : AnyShapeStyle(.secondary))
                .readableText(text)
                .accessibilityIdentifier("chat.\(paneID).note")
        }
    }
}

struct WorkingRow: View {
    let since: Date?

    var body: some View {
        HStack(spacing: 6) {
            StateIcon(state: .working)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(since.map { "Working " + ChatHistory.duration(context.date.timeIntervalSince($0)) } ?? "Working")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
    }
}

struct UserBubble: View {
    let text: String
    let paneID: String
    var sending = false
    @Environment(\.look) private var look

    var body: some View {
        // Its own line breaks kept: Markdown joins a paragraph's lines.
        Markdown(text: text.replacingOccurrences(of: "\n", with: "  \n"))
            .accessibilityValue(text)
            .accessibilityIdentifier("chat.\(paneID).\(sending ? "sending" : "user")")
            .foregroundStyle(Look.onAccent)
            .environment(\.chatLink, Look.onAccent)
            .bubble(look.sentBubble)
            .padding(.trailing, -Bubble.inset)
            .padding(.leading, ChatView.gutter)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

extension View {
    /// The caller pulls it out by `Bubble.inset`, so that its text keeps the messages' edge.
    func bubble(_ color: Color) -> some View {
        padding(.horizontal, Bubble.inset).padding(.vertical, 7).background(color, in: .rect(cornerRadius: 15))
    }

    /// Pulled out by `inset`, so that its text keeps the messages' edge.
    func replyPlace(_ inset: CGFloat = Composer.inset) -> some View {
        padding(.leading, -inset).padding(.trailing, ChatView.gutter)
    }
}

/// Messages' padding (iMessage: 12 pt beside the text, 7 pt above and under it).
enum Bubble {
    static let inset: CGFloat = 12
}

private struct Plan: View {
    let todos: [ChatTodo]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Plan").foregroundStyle(.secondary)
                Spacer()
                Text("\(todos.count(where: \.done)) of \(todos.count)").foregroundStyle(.tertiary)
            }
            ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                Label {
                    Text(todo.text).strikethrough(todo.done).foregroundStyle(todo.done ? .secondary : .primary)
                } icon: {
                    Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(todo.active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            }
        }
        .font(.system(size: 12))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 8))
    }
}

struct QuestionCard: View {
    let question: ChatQuestion
    let paneID: String
    let answer: ([String: String]) -> Void
    @State private var answers: [String: String] = [:]
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(question.items, id: \.text) { item in
                Label(item.text, systemImage: "questionmark.circle.fill").font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(look.needsYou)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.options, id: \.self) { option in
                        Button { pick(option, for: item) } label: {
                            Text(option).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.glass)
                        .tint(answers[item.text] == option ? .accentColor : nil)
                        .accessibilityIdentifier("chat.\(paneID).option.\(option)")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(look.needsYou.opacity(0.12)), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.\(paneID).question")
    }

    private func pick(_ option: String, for item: ChatQuestion.Item) {
        guard !question.answered else { return }
        answers[item.text] = option
        if answers.count == question.items.count {
            answer(answers)
        }
    }
}

private extension ChatRow {
    var user: Bool {
        if case .user = self {
            true
        } else {
            false
        }
    }
}

private struct Dim: ViewModifier {
    var opacity = Chat.Outgoing.dimmed

    func body(content: Content) -> some View {
        content.opacity(opacity)
    }
}

/// Not observed: it changes at every scroll frame.
@MainActor
final class Tops {
    var places: [String: CGFloat] = [:]
    var held: (id: String, by: CGFloat)?

    func hold(at offset: CGFloat, bottom: Bool) {
        let above = places.lazy.filter { $0.value <= offset }
        let row = bottom ? nil : above.max { $0.value < $1.value } ?? places.min { $0.value < $1.value }
        held = row.map { ($0.key, offset - $0.value) }
    }
}

struct Rows: View {
    let chat: Chat
    let rows: ArraySlice<ChatRow>
    let tops: Tops
    /// Not for rows that come with a history or an earlier block: dim means not taken yet.
    let fades: Bool
    let restore: (CGFloat) -> Void
    @State private var opened: Set<String> = []
    @State private var openTools: Set<String> = []

    var body: some View {
        ForEach(rows) { row in
            ChatRowView(row: row, paneID: chat.paneID, counts: counts(row), steps: steps(row),
                        toggle: { opened.formSymmetricDifference([row.id]) }, opened: openTools,
                        toggleTool: { openTools.formSymmetricDifference([$0]) })
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(ChatMessages.space)).minY } action: { top in
                    tops.places[row.id] = top
                    if let held = tops.held, held.id == row.id {
                        restore(top + held.by)
                    }
                }
                .onDisappear { tops.places[row.id] = nil }
                .transition(fades && row.user ? Self.taken : .identity)
        }
    }

    /// A message comes in dimmed, as its bubble showed until the agent took it.
    private static var taken: AnyTransition {
        .asymmetric(insertion: .modifier(active: Dim(), identity: Dim(opacity: 1)), removal: .identity)
            .animation(.fade)
    }

    /// Copied: a slice would hold the history's entries, and each new entry would copy them all.
    private func steps(_ row: ChatRow) -> [ChatEntry]? {
        guard case let .stack(id, steps) = row, opened.contains(id) else { return nil }
        let entries = chat.history.entries
        return Array(entries[steps.clamped(to: entries.indices)])
    }

    private func counts(_ row: ChatRow) -> String {
        guard case let .stack(_, steps) = row else { return "" }
        let entries = chat.history.entries
        return ChatTool.summary(entries[steps.clamped(to: entries.indices)].compactMap(\.tool))
    }
}
