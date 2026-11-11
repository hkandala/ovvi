import AppKit
import HerdrKit
import SwiftUI

/// SwiftUI brings an open window of an equal value to the front.
struct Floating: Codable, Hashable {
    let session: String
    let terminalID: String
}

extension Page {
    func floats(_ pane: HostStore.Pane) -> Bool {
        pane.terminalID.map { floating[$0] != nil } ?? false
    }

    func hasKeyboard(_ paneID: String) -> Bool {
        keyboardPane?.id == paneID || store.pane(paneID).map(floats) == true
    }

    /// Once a snapshot has it.
    func floatNew(_ made: HerdrKit.Pane) async {
        try? await Ovvi.settle { store.pane(made.id)?.terminalID != nil }
        if let pane = store.pane(made.id) {
            float(pane)
        }
    }

    /// herdr keeps the pane in its tab.
    func float(_ pane: HostStore.Pane, agent: Bool = false) {
        guard let terminalID = pane.terminalID else { return }
        if floating[terminalID] != nil {
            if !agent {
                terminals.focus(terminalID)
            }
        } else if !WindowPages.windows.contains(where: { $0.floats(terminalID) }) {
            floating[terminalID] = false
            if zoomedPaneID == pane.id {
                zoomedPaneID = nil
            }
            focusKeyboardCard()
        }
        FloatFrames.open(Floating(session: id, terminalID: terminalID), over: terminals.pages?.window, agent: agent,
                         with: WindowPages.openWindow)
    }
}

extension WindowPages {
    static func float(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard url.host() == "float", let session = value("session"), let pane = value("pane") else { return }
        float(session: session, pane: pane, machine: value("machine") ?? Machine.thisMac.id)
    }

    static func float(session: String, pane: String, machine: String, over: WindowPages? = nil, agent: Bool = false) {
        // Any app or pane can ask: the name goes into a herdr argv.
        guard Session.isValidName(session) else {
            windows.first?.cannotFloat(pane, of: session, "not a session name.")
            return
        }
        guard let window = over ?? windows.first(where: { $0.machine.id == machine }) else {
            if windows.isEmpty {
                ask(machine, session) { float(session: session, pane: pane, machine: machine, agent: agent) }
            } else {
                windows.first?.cannotFloat(pane, of: session, "no window of machine \(machine).")
            }
            return
        }
        if let old = window.floatPending?.page, old.floating.isEmpty {
            window.dropFloatOnly(old)
        }
        window.floatPending = (window.pageToFloat(session), pane)
        window.floatPendingForAgent = agent
        window.showFloatPending()
    }

    func floats(_ terminalID: String) -> Bool {
        withFloats.contains { $0.floating[terminalID] != nil }
    }

    var withFloats: [Page] {
        list + floatOnly
    }

    private func pageToFloat(_ session: String) -> Page {
        if let page = withFloats.first(where: { $0.id == session }) {
            return page
        }
        let store = HostStore.named(session, on: machine)
        store.windows.append(self)
        let page = Page(store: store, terminals: terminals)
        floatOnly.append(page)
        return page
    }

    func dropFloatOnly(_ page: Page) {
        guard let index = floatOnly.firstIndex(where: { $0 === page }) else { return }
        floatOnly.remove(at: index)
        leave(page.store)
        showTerminals()
    }

    func showFloatPending() {
        guard let (page, paneID) = floatPending, page.store.state != .connecting else { return }
        floatPending = nil
        if let pane = page.store.panes.first(where: { $0.id == paneID && $0.terminalID != nil }) {
            page.float(pane, agent: floatPendingForAgent)
            // It streams at once, not at the next snapshot: its page may not be in view.
            showTerminals()
        } else {
            let why = if case let .failed(error) = page.store.state {
                error.localizedDescription
            } else {
                "no such pane."
            }
            if !floatPendingForAgent {
                cannotFloat(paneID, of: page.id, why)
            }
        }
        if page.floating.isEmpty {
            dropFloatOnly(page)
        }
    }

    private func cannotFloat(_ pane: String, of session: String, _ why: String) {
        let notice = Notice(text: "Can't float pane \(pane) of \(session): \(why)", tone: .warning)
        current?.store.show(notice)
    }
}
