import HerdrKit
import SwiftUI

struct AskDialog: View {
    let question: WindowPages.Question
    let machine: Machine
    @State private var answer = ""
    @FocusState private var focused: Bool

    var body: some View {
        let hostKey = question.text.contains("(yes/no")
        VStack(alignment: .leading, spacing: 12) {
            Label(machine.name, systemImage: machine.icon).font(.system(size: 13, weight: .semibold))
            Text(hostKey ? Self.facts(question.text) : question.text
                .trimmingCharacters(in: .whitespacesAndNewlines))
                .font(hostKey ? .system(size: 12).monospaced() : .system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ask.text")
            if !hostKey {
                HStack(spacing: 6) {
                    Image(systemName: "key").foregroundStyle(.secondary).accessibilityHidden(true)
                    SecureField("", text: $answer)
                        .accessibilityLabel("Answer")
                        .focused($focused)
                        .focusSoon($focused)
                        .onSubmit { question.answer(answer) }
                        .accessibilityIdentifier("ask.answer")
                }
                .fieldCapsule().background(.background.opacity(0.6), in: .capsule)
                .overlay(Capsule().strokeBorder(.primary.opacity(0.2)))
            }
            HStack {
                Spacer()
                Button("Cancel") { question.answer(nil) }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                Button(hostKey ? "Connect" : "OK") { question.answer(hostKey ? "yes" : answer) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("ask.ok")
            }
        }
        .onAppear { AccessibilityNotification.Announcement(question.text).post() }
    }

    static func facts(_ text: String) -> String {
        text.split(separator: "\n").filter { !$0.contains("(yes/no") }.joined(separator: "\n")
            .replacing(#/fingerprint is:? /#, with: "fingerprint is:\n")
    }
}

extension View {
    func dialog() -> some View {
        Color.clear.contentShape(.rect).onTapGesture {}
            .overlay {
                padding(20).frame(width: 440).floatingGlass(in: .panel)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
            }
    }
}
