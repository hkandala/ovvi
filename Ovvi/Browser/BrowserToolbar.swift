import HerdrKit
import SwiftUI
import WebKit

struct BrowserToolbar: View {
    let browser: Browser
    let page: Page
    @State private var text = ""
    @FocusState private var editing: Bool
    @State private var hovering = false
    @Environment(\.look) private var look

    var body: some View {
        let id = "browser.\(browser.paneID)"
        HStack(spacing: 6) {
            // No opacity of their own: ChromeStyle dims a disabled button.
            HStack(spacing: 0) {
                IconButton(symbol: "chevron.left", help: "Back", size: 22) { browser.view.goBack() }
                    .disabled(!browser.canGoBack)
                    .accessibilityIdentifier("\(id).back")
                IconButton(symbol: "chevron.right", help: "Forward", size: 22) { browser.view.goForward() }
                    .disabled(!browser.canGoForward)
                let loading = browser.loading
                IconButton(symbol: loading ? "xmark" : "arrow.clockwise", help: loading ? "Stop" : "Reload", size: 22) {
                    browser.loading ? browser.view.stopLoading() : browser.reload()
                }
                .disabled(!browser.loaded)
                .accessibilityIdentifier("\(id).reload")
            }
            .foregroundStyle(look.paneButton)
            address(id)
            IconButton(symbol: "hammer", help: "Web Inspector", key: .init("i", modifiers: [.command, .option]),
                       size: 22, action: browser.view.showInspector)
                .disabled(!browser.loaded)
                .foregroundStyle(look.paneButton)
                .accessibilityIdentifier("\(id).inspector")
        }
        .blursWhenHidden($editing)
    }

    private func address(_ id: String) -> some View {
        TextField("Ask Google or type a URL", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .focused($editing)
            // On the field, before the overlay that would take it too.
            .accessibilityIdentifier("\(id).address")
            // Its text hidden under the shown address while not editing; not by opacity: SwiftUI focuses no view at
            // opacity 0.
            .foregroundStyle(editing ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear))
            .overlay(alignment: .leading) {
                if !editing {
                    shown.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(.rect)
                        .onTapGesture { editing = true }
                }
            }
            // A remote machine's name: its `localhost` is that machine's. A click loads through This Mac's network.
            .safeAreaInset(edge: .trailing, spacing: 4) {
                if remote {
                    machine.accessibilityIdentifier("\(id).machine")
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, remote ? 4 : 10)
            .frame(minWidth: 120, maxWidth: .infinity, minHeight: 26, maxHeight: 26)
            .background(Capsule().fill(.primary.opacity(hovering && !editing ? 0.1 : 0.06)))
            .pointerStyle(.horizontalText).onHover { hovering = $0 }
            .overlay {
                Capsule().strokeBorder(editing ? Color.accentColor : .primary.opacity(0.08),
                                       lineWidth: editing ? 1.5 : 0.5)
            }
            .focusEffectDisabled()
            .onSubmit { browser.go(text) }
            .onExitCommand {
                text = browser.address
                browser.view.takeKeyboard()
            }
            .onChange(of: browser.address, initial: true) {
                if !editing {
                    text = browser.address
                }
            }
            .onChange(of: editing) {
                guard editing else {
                    text = browser.address
                    return
                }
                page.tookKeyboard(browser.terminalID)
                // Selected whole once the field has the keyboard, in its editor only: a web view that took the keyboard
                // meanwhile would select its whole page.
                DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSText)?.selectAll(nil) }
            }
            .onChange(of: browser.wantsAddress, initial: true) {
                guard browser.wantsAddress else { return }
                browser.wantsAddress = false
                focus(tries: 10)
            }
    }

    private var remote: Bool {
        page.store.machine.isRemote
    }

    private var machine: some View {
        let name = page.store.machine.name, mac = browser.viaMac
        return Button(action: browser.toggleNetwork) {
            Text(mac ? Machine.thisMac.name : name).font(.system(size: 11)).lineLimit(1)
                .foregroundStyle(mac ? AnyShapeStyle(.secondary) : AnyShapeStyle(look.needsYou))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(mac ? Color.primary.opacity(0.08) : look.needsYou.opacity(0.18)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.default)
        .fixedSize()
        .help(mac ? "Load through \(name)" : "Load through This Mac's network")
    }

    /// From the next turn (a first responder set during an update is undone), again every 50 ms while a card just
    /// made is not in its window yet, as long as it is still this card's turn and no panel has the keys.
    private func focus(tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (tries == 10 ? 0 : 0.05)) {
            guard !editing, tries > 0, let pane = page.store.pane(browser.paneID),
                  page.floats(pane) || page.terminals.pages?.panelOpen != true && page.keyboardCard(pane.tabID) === pane
            else { return }
            editing = true
            focus(tries: tries - 1)
        }
    }

    /// The address, or the prompt: the field's own is hidden with its text.
    private var shown: some View {
        Group {
            if browser.address.isEmpty {
                Text("Ask Google or type a URL").foregroundStyle(.tertiary)
            } else {
                addressText(browser.address)
            }
        }
        .font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
    }
}

func addressText(_ address: String) -> Text {
    let url = URL(string: address)
    let host = url.flatMap { url in url.host.map { $0 + (url.port.map { ":\($0)" } ?? "") } }
    let rest = host.map { address.components(separatedBy: $0).dropFirst().joined(separator: $0) } ?? ""
    return Text("\(Text(host ?? address))\(Text(rest).foregroundStyle(.secondary))")
}
