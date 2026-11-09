import AppKit
import HerdrKit
import SwiftUI

extension Page {
    /// A plugin pane's card, made on first use; nil for a browser's and every other pane.
    func plugin(_ pane: HostStore.Pane) -> Plugin? {
        guard let terminalID = pane.terminalID, let label = pane.plugin else { return nil }
        return terminals.plugin(pane, label, terminalID: terminalID, store: store)
    }
}

/// The card's content under its header, its plugin's page, with the toast at its top.
struct PluginCard: View {
    let plugin: Plugin
    let page: Page
    /// False in an overview tile, which leaves the keyboard to the card.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        WebCardContent(card: plugin.web)
            // A card made again (Reload Plugin over a changed manifest) hosts its own web view and themes it, which
            // starts its page: the old view's host and `onChange` would keep the old one.
            .id(ObjectIdentifier(plugin))
            // Over the page alone, as the page is.
            .overlay {
                if let failure = plugin.web.bridge?.failure {
                    PluginFailure(plugin: plugin, problem: failure)
                } else if !PluginTrust.shared.allows(plugin.manifest) {
                    TrustPrompt(plugin: plugin, page: page)
                }
            }
            .padding([.horizontal, .bottom], PaneCard.inset)
            // Over a page that has not drawn yet (a big tree's first listing, a remote file).
            .overlay {
                if DefaultPlugins.shared.installing.contains(plugin.manifest.id), !plugin.web.ready {
                    // A default plugin's first launch: its copy and `npm ci`, a few seconds.
                    PluginLoader(plugin: plugin.manifest, verb: "Installing")
                        .accessibilityIdentifier("pane.\(plugin.paneID).installing")
                } else if !plugin.web.ready {
                    Loader(id: "pane.\(plugin.paneID).loading", delay: .milliseconds(150))
                }
            }
            .overlay(alignment: .top) {
                if let toast = plugin.web.toast {
                    ToastView(toast: toast, plugin: plugin).padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: plugin.web.toast == nil)
            // In place of the card that had the keyboard.
            .onAppear {
                if isEnabled, page.hasKeyboard(plugin.paneID) {
                    plugin.web.view.takeKeyboard()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(plugin.manifest.id).\(plugin.paneID).card")
    }
}

/// One line and two buttons over the card's top, on glass.
private struct ToastView: View {
    let toast: Toast
    let plugin: Plugin
    @Environment(\.look) private var look

    var body: some View {
        let id = "pane.\(plugin.paneID).toast"
        HStack(spacing: 10) {
            Text(toast.text).lineLimit(1).accessibilityIdentifier(id)
            if let other = toast.other {
                Button(other.title, role: other.role) {
                    plugin.web.toast = nil
                    other.run()
                }
                .buttonStyle(.glass)
                // The role alone draws nothing on glass. A red label: a red fill would read as a second default.
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
        // Capsules the same 7 pt inside the toast's capsule all round: a rounded rectangle's corner ran into its curve.
        .buttonBorderShape(.capsule)
        .padding(.leading, 14).padding([.trailing, .vertical], 7)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Why a plugin's page cannot load (`PluginProblem`): the title, the error's lines, its fix (Reload, Try Again or
/// Build) and Show Log.
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
        // Over what the page drew before it stopped.
        .background(look.cardSolid(keyboard: lit))
    }

    /// Build runs the package's build script first; Reload and Try Again load the page again.
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

/// While a browser or a plugin pane takes the chooser's place, or a browser card is built.
struct PluginLoader: View {
    let plugin: PluginManifest
    var verb = "Opening"

    var body: some View {
        Loader(symbol: plugin.icon, text: "\(verb) \(plugin.name)…")
    }
}

/// The card of a label naming a plugin not on this Mac (removed, or from another Mac): the plugin id and the
/// argument. The label stays, so the card comes back with the plugin. A plugin with no page yet shows its loader.
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

    /// A package with the id whose manifest is wrong says what is wrong.
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

/// A floated plugin pane: its second row under the floating window's title row, then its content.
struct FloatingPlugin: View {
    let plugin: Plugin
    let page: Page

    var body: some View {
        VStack(spacing: 0) {
            // A plugin with no header and no Back and Forward has no row, as in a pane.
            if plugin.manifest.hasRow {
                PluginHeader(plugin: plugin, page: page).padding(.horizontal, 11).frame(height: PaneCard.header)
                    .padding(.top, PaneCard.floatingTop)
            }
            PluginCard(plugin: plugin, page: page)
        }
    }
}

/// Unsaved edits, after the title in the card's header and the floating window's title row: 7 pt, centered on the
/// title's x-height (a little under the line's middle), as a document window's.
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
