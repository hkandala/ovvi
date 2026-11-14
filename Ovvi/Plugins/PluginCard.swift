import AppKit
import HerdrKit
import SwiftUI

extension Page {
    func plugin(_ pane: HostStore.Pane) -> Plugin? {
        guard let terminalID = pane.terminalID, let label = pane.plugin else { return nil }
        return terminals.plugin(pane, label, terminalID: terminalID, store: store)
    }
}

struct PluginCard: View {
    let plugin: Plugin
    let page: Page

    var body: some View {
        WebCardContent(card: plugin.web)
            // A card made again hosts its own web view: a kept host and `onChange` would hold the replaced one.
            .id(ObjectIdentifier(plugin))
            .overlay {
                if let failure = plugin.web.bridge?.failure {
                    PluginFailure(plugin: plugin, problem: failure)
                } else if !PluginTrust.shared.allows(plugin.manifest) {
                    TrustPrompt(plugin: plugin, page: page)
                }
            }
            .padding([.horizontal, .bottom], PaneCard.inset)
            .overlay {
                if DefaultPlugins.shared.installing.contains(plugin.manifest.id), !plugin.web.ready {
                    PluginLoader(plugin: plugin.manifest, verb: "Installing")
                        .accessibilityIdentifier("pane.\(plugin.paneID).installing")
                } else if !plugin.web.ready {
                    Loader(id: "pane.\(plugin.paneID).loading", delay: .milliseconds(150))
                }
            }
            .overlay(alignment: .top) {
                if let toast = plugin.web.toast {
                    ToastView(toast: toast, plugin: plugin).padding(.top, 6).padding(.horizontal, PaneCard.inset)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(Animation.reduced ? nil : .easeOut(duration: 0.15), value: plugin.web.toast == nil)
            .onAppear {
                if page.hasKeyboard(plugin.paneID) {
                    plugin.web.view.takeKeyboard()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(plugin.manifest.id).\(plugin.paneID).card")
    }
}

private struct ToastView: View {
    let toast: Toast
    let plugin: Plugin
    @Environment(\.look) private var look

    var body: some View {
        let id = "pane.\(plugin.paneID).toast"
        Capped(width: Notice.width) {
            HStack(spacing: 8) {
                Text(toast.text).lineLimit(1).help(toast.text).accessibilityIdentifier(id)
                if let other = toast.other {
                    Button(other.title, role: other.role) {
                        plugin.web.toast = nil
                        other.run()
                    }
                    .buttonStyle(.glass)
                    // The role alone draws nothing on glass.
                    .foregroundStyle(other.role == .destructive ? look.error : Color.primary)
                    .accessibilityIdentifier("\(id).other")
                }
                Button(toast.main.title, role: toast.main.role) {
                    plugin.web.toast = nil
                    toast.main.run()
                }
                .buttonStyle(.glassProminent)
                .tint(toast.main.role == .destructive ? look.error : nil)
                .accessibilityIdentifier("\(id).main")
            }
            .controlSize(.small)
            // A rounded rectangle's corner runs into the toast capsule's curve.
            .buttonBorderShape(.capsule)
            .padding(.leading, 14).padding([.trailing, .vertical], 7)
        }
        .glassEffect(.regular, in: .capsule)
    }
}

private struct PluginFailure: View {
    let plugin: Plugin
    let problem: PluginProblem
    @State private var building = false
    @Environment(\.look) private var look
    @Environment(\.litCard) private var lit

    var body: some View {
        let id = "pane.\(plugin.paneID)"
        EmptyState(
            symbol: plugin.manifest.icon,
            title: problem.title,
            text: problem.text,
            code: true,
            id: "\(id).failure",
        ) {
            if building {
                ProgressView().controlSize(.small)
            } else if let button = problem.button {
                Button(button) { fix() }.buttonStyle(.glassProminent)
                    .accessibilityIdentifier(problem.builds ? "\(id).build" : "\(id).reload")
            }
            Button("Show Log") { PluginLog.show(plugin.manifest.id) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(look.cardSolid(keyboard: lit))
    }

    private func fix() {
        guard problem.builds else { return plugin.web.reload() }
        building = true
        Task {
            defer { building = false }
            if let problem = await PluginBuilds.shared.build(plugin.manifest) {
                plugin.web.bridge?.failure = problem
            } else {
                plugin.web.reload()
            }
        }
    }
}

struct PluginLoader: View {
    let plugin: PluginManifest
    var verb = "Opening"

    var body: some View {
        Loader(symbol: plugin.icon, text: "\(verb) \(plugin.name)…")
    }
}

struct MissingPlugin: View {
    let label: PaneLabel
    let pane: HostStore.Pane
    let page: Page

    var body: some View {
        if let plugin = label.manifest {
            PluginLoader(plugin: plugin)
        } else {
            missing
        }
    }

    private var missing: some View {
        let problem = Registry.problem(label.plugin), id = "pane.\(pane.id)"
        let title = problem == nil ? "\(label.plugin) is not on this Mac" : "\(label.plugin) did not load"
        let text = problem ?? label.arg
        return EmptyState(
            symbol: Registry.missing,
            title: title,
            text: text,
            code: problem != nil,
            id: "\(id).missing",
        ) {
            Button("Show Placeholder") { pane.placeholder = true }.accessibilityIdentifier("\(id).show-placeholder")
            Button("Close Pane") { page.closePane(pane) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FloatingPlugin: View {
    let plugin: Plugin
    let page: Page

    var body: some View {
        VStack(spacing: 0) {
            if plugin.manifest.hasRow {
                PluginHeader(plugin: plugin, page: page).padding(.horizontal, 11).frame(height: PaneCard.header)
                    .padding(.top, PaneCard.floatingTop)
            }
            PluginCard(plugin: plugin, page: page)
        }
    }
}

struct DirtyDot: View {
    let paneID: String
    private nonisolated static let drop: CGFloat = {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return (font.ascender + font.descender - font.xHeight) / 2
    }()

    var body: some View {
        Circle().fill(.secondary).frame(width: 7, height: 7)
            .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] - Self.drop }
            .padding(.horizontal, 3)
            .help("Edited")
            .accessibilityElement()
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel("Edited")
            .accessibilityIdentifier("pane.\(paneID).dirty")
    }
}
