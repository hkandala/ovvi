import HerdrKit
import SwiftUI

struct NewPane: View {
    let chooser: Chooser
    let page: Page
    let cardID: String
    private var fade: Animation? {
        Animation.reduced ? nil : .easeOut(duration: 0.15)
    }

    @Environment(\.look) private var look
    @AccessibilityFocusState private var focus: Chooser.Row?
    @State private var pointer = NSEvent.mouseLocation
    private static let row: CGFloat = 28, spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Group {
                if let agent = chooser.starting {
                    loader(agent)
                } else if let plugin = chooser.opening {
                    PluginLoader(plugin: plugin).accessibilityIdentifier("pane.\(cardID).loader")
                } else {
                    let rows = chooser.rows, width = max(0, min(300, size.width - 24))
                    let height = CGFloat(rows.count) * (Self.row + Self.spacing) - Self.spacing
                    let folder = size.height - 16 >= height + 12 + NewPaneFolder.height
                    VStack(spacing: 12) {
                        list(rows, details: size.width >= 300, scrolls: height > size.height - 16)
                            .frame(width: width, height: max(0, min(height, size.height - 16)))
                        if folder {
                            NewPaneFolder(chooser: chooser, page: page, cardID: cardID)
                                .frame(width: width, height: NewPaneFolder.height)
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .animation(fade, value: chooser.starting)
        .animation(fade, value: chooser.open)
        .animation(fade, value: chooser.opening)
        .onAppear {
            focus = chooser.selected
            Latency.shared.step("list")
        }
        .onChange(of: chooser.selected) { pointer = NSEvent.mouseLocation }
        .onChange(of: runs, initial: true) {
            if runs, chooser.starting == nil, chooser.opening == nil {
                page.store.drop(chooser)
            }
        }
    }

    private var runs: Bool {
        page.store.pane(cardID).map { $0.agent != nil || $0.program?.isShell == false && !$0.starting } ?? false
    }

    /// A scroll view only on a card lower than the list: an AppKit view of its own, it is the list's dearest part to
    /// make.
    @ViewBuilder
    private func list(_ rows: [Chooser.Row], details: Bool, scrolls: Bool) -> some View {
        let stack = VStack(spacing: Self.spacing) {
            ForEach(rows, id: \.self) { row in
                self.row(row, details: details).id(row)
            }
        }
        Group {
            if scrolls {
                ScrollViewReader { proxy in
                    ScrollView { stack }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollIndicators(.never)
                        .onChange(of: chooser.selected) { proxy.scrollTo(chooser.selected) }
                }
            } else {
                stack
            }
        }
        .animation(nil, value: scrolls)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New Pane")
    }

    private func row(_ row: Chooser.Row, details: Bool) -> some View {
        let selected = chooser.selected == row, (name, detail) = row.labels
        let agent = row.agent, missing = Chooser.missing(row, page.terminals.pages?.agents)
        let dim = selected ? AnyShapeStyle(Look.onAccent.opacity(0.75))
            : look.contrast ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
        return Button {
            if let pane = page.store.pane(cardID) {
                page.go(to: pane)
            }
            page.store.pick(chooser, row, page: page)
        } label: {
            HStack(spacing: 8) {
                icon(row, selected: selected)
                Text(name).lineLimit(1)
                if row == .agent {
                    Image(systemName: chooser.open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(dim)
                }
                Spacer(minLength: 4)
                if details, !missing {
                    Text(detail).font(.system(size: 12, design: agent != nil ? .monospaced : .default))
                        .foregroundStyle(dim).lineLimit(1)
                }
                if missing {
                    Text("Not installed").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                } else if let number = chooser.number(row) {
                    Text("\(number)").font(.system(size: 11)).monospacedDigit().foregroundStyle(dim)
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(Look.onAccent) : AnyShapeStyle(.primary))
            .padding(.leading, agent != nil ? 28 : 8)
            .padding(.trailing, 8)
            .frame(height: Self.row)
        }
        .buttonStyle(ChromeStyle(selected: selected, tint: .accentColor))
        .disabled(missing)
        .help(missing ? "Install \(name): \(agent?.install ?? "")" : "")
        .onContinuousHover { phase in
            if case .active = phase, !missing, NSEvent.mouseLocation != pointer {
                chooser.selected = row
            }
        }
        .accessibilityLabel(name)
        .accessibilityValue(row == .agent ? chooser.open ? "expanded" : "collapsed" : missing ? "Not installed" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityFocused($focus, equals: row)
        .accessibilityIdentifier("pane.\(cardID).chooser.\(row.id)")
    }

    private func icon(_ row: Chooser.Row, selected: Bool) -> some View {
        Group {
            switch row {
            case .terminal: Image(systemName: "terminal")
            case .agent: Image(systemName: "sparkles")
            case let .plugin(id): Image(symbol: Registry.plugin(id)?.icon ?? Registry.missing)
            case .start: ProgramTile(icon: row.id)
            }
        }
        .foregroundStyle(selected ? AnyShapeStyle(Look.onAccent.opacity(0.75))
            : row == .agent && chooser.open ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(width: 22)
    }

    private func loader(_ agent: Chooser.Agent) -> some View {
        Loader(text: "Starting \(agent.name)…", id: "pane.\(cardID).loader") {
            ProgramTile(icon: agent.command).scaleEffect(2).frame(width: 44, height: 36)
        }
    }
}

struct NewPaneOverlay: View {
    let chooser: Chooser?
    let page: Page
    let cardID: String

    var body: some View {
        ZStack {
            if let chooser {
                NewPane(chooser: chooser, page: page, cardID: cardID).transition(.opacity)
            }
        }
        .animation(Animation.reduced ? nil : .easeOut(duration: 0.15), value: chooser == nil)
    }
}
