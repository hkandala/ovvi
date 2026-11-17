import HerdrKit
import SwiftUI

extension AgentState {
    var word: String {
        switch self {
        case .needsYou: "needs you"
        case .working: "working"
        case .finishedUnseen: "finished"
        case .idle: "idle"
        }
    }

    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .finishedUnseen: "Done"
        case .idle: "Idle"
        }
    }

    var shown: AgentState? {
        self == .idle ? nil : self
    }

    func label(_ look: Look) -> StateLabel? {
        self == .idle ? nil : StateLabel(text: title, icon: self, color: color(look))
    }

    var calls: Bool {
        self >= .finishedUnseen
    }

    func color(_ look: Look) -> Color {
        switch self {
        case .needsYou: look.needsYou
        case .working: look.working
        case .finishedUnseen: look.finished
        case .idle: .secondary
        }
    }
}

struct AgentsWatch: ViewModifier {
    let pages: WindowPages
    let page: Page
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        // A window with no page shows no badge.
        let needsYou = pages.list.isEmpty ? 0 : HostStore.needsYou
        let card = page.keyboardCard(page.selectedTab?.id)
        let looked = [page.id, page.selectedTab?.id ?? "", card?.id ?? ""]
        content
            .testValue("app.badge", "Dock Badge", "\(needsYou)")
            .onChange(of: needsYou, initial: true) { HostStore.showBadge() }
            .onChange(of: looked + [appearsActive ? "key" : ""], initial: true) {
                pages.look(key: appearsActive)
                if appearsActive {
                    HostStore.look(card, in: page.store)
                }
            }
    }
}
