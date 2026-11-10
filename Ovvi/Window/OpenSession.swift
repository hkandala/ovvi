import HerdrKit
import SwiftUI

struct OpenSession: View {
    let pages: WindowPages
    @Binding var open: Bool
    @State private var suggested: String
    @State private var busy: String?
    @State private var failure: (text: String, retry: () -> Void)?
    @State private var asking: (verb: String, session: String)?

    init(pages: WindowPages, open: Binding<Bool>) {
        self.pages = pages
        _open = open
        _suggested = State(initialValue: (pages.current?.store.sessions ?? []).newName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilterList(prompt: "Name a new session, or find one", name: "open-session", items: items,
                       maxHeight: 320, inset: failure == nil ? 8 : 0) {}
            if let failure {
                NoticeCapsule(tone: .error, text: failure.text) {
                    Button("Retry", action: failure.retry).accessibilityIdentifier("notice.retry")
                }
                .accessibilityIdentifier("open-session.notice")
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }
        }
        .padding([.horizontal, .top], 8)
        .frame(width: 420)
        .floatingGlass(in: .panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open Session")
        .onAppear { Latency.shared.note("open-session \(sessions.map(\.name).joined(separator: ","))") }
        .task {
            await pages.current?.store.loadSessions()
            if sessions.contains(where: { $0.name == suggested }) {
                suggested = sessions.newName
            }
        }
        .alert(
            "\(asking?.verb.capitalized ?? "") the session “\(asking?.session ?? "")”?",
            isPresented: Binding { asking != nil } set: {
                if !$0 {
                    asking = nil
                }
            },
            presenting: asking,
        ) { asked in
            Button("\(asked.verb.capitalized) Session", role: .destructive) {
                run(asked.session, asked.verb) {
                    let client = await HerdrClient(session: asked.session, exec: pages.machine.exec())
                    if asked.verb == "stop" {
                        try await client.stopSession()
                    } else {
                        try await client.deleteSession()
                    }
                    await pages.current?.store.loadSessions()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { asked in
            Text(asked.verb == "stop"
                ? "Every program in it will end, here and in every herdr client. Its spaces and tabs stay "
                + "for its next start."
                : "Its spaces, tabs and panes go for good. This cannot be undone.")
        }
    }

    private var sessions: [Session] {
        pages.current?.store.sessions ?? []
    }

    private func items(_ filter: String) -> [FilterList.Item] {
        let shown = pages.list.map(\.id)
        let typed = filter.trimmingCharacters(in: .whitespaces)
        let new = typed.isEmpty ? suggested : typed
        let create = Session.isValidName(new) && !sessions.contains { $0.name == new } && !shown.contains(new)
            ? [item("new", "Create session “\(new)”", "New", new) { start(new) }] : []
        let others = sessions.filter { !shown.contains($0.name) && $0.name.matches(filter) }
        let place = pages.machine.isRemote ? " on \(pages.machine.name)" : ""
        let session = { (one: Session) in
            var row = item("session", one.name, (one.running ? "Running" : "Stopped") + place, one.name) {
                start(one.name)
            }
            let verb = one.running ? "stop" : "delete"
            row.buttonRole = .destructive
            row.button = (verb.capitalized, {
                if busy == nil {
                    asking = (verb, one.name)
                }
            })
            return row
        }
        return create + others.filter(\.running).map(session) + others.filter { !$0.running }.map(session)
            + pages.list.filter { $0.id.matches(filter) }.map { page in
                var row = item("open", page.id, "Open in this window", page.id) {
                    pages.show(page)
                    open = false
                }
                if pages.canDetach {
                    row.button = ("Detach", { pages.close(page) })
                }
                return row
            }
    }

    private func item(_ kind: String, _ title: String, _ section: String, _ session: String,
                      act: @escaping () -> Void) -> FilterList.Item
    {
        FilterList.Item(
            id: "\(kind).\(session)",
            symbol: ["new": "plus", "open": "checkmark"][kind] ?? "rectangle.stack",
            title: title,
            section: section,
            busy: busy == session,
        ) {
            if busy == nil {
                act()
            }
        }
    }

    private func start(_ session: String) {
        let machine = pages.machine
        run(session, "start") {
            try await HostStore.start(session, on: machine)
            if pages.machine.id == machine.id {
                pages.open(session)
            }
            open = false
        }
    }

    private func run(_ session: String, _ verb: String, _ work: @escaping () async throws -> Void) {
        guard busy == nil else { return }
        busy = session
        failure = nil
        Task {
            do {
                try await work()
            } catch {
                failure = ("Could not \(verb) \(session). \(error.localizedDescription)", {
                    run(session, verb, work)
                })
            }
            busy = nil
        }
    }
}

extension [Session] {
    var newName: String {
        let first = ["amber", "brisk", "calm", "early", "lunar", "misty", "quiet", "sunny"]
        let second = ["cedar", "dune", "grove", "harbor", "meadow", "peak", "ridge", "river"]
        let names = first.flatMap { word in second.map { "\(word)-\($0)" } }
        return names.shuffled().first { name in !contains { $0.name == name } } ?? "session-\(count + 1)"
    }
}
