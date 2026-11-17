import HerdrKit
import SwiftUI

/// The page in view's header, over the pages: a session change slides only the spaces. Its title opens a shelf with the
/// window's other sessions and Open Session.
struct SessionHeader: View {
    let pages: WindowPages
    let page: Page
    let openSession: () -> Void
    @State private var open = false
    @State private var over = false
    @State private var plus = false
    /// The row under the pointer or the arrows: the other sessions, then Open Session.
    @State private var lit: Int?
    @FocusState private var focused: Bool

    var body: some View {
        let others = pages.list.filter { $0 !== page }
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                title
                Spacer(minLength: gap)
                IconButton(symbol: "square.grid.2x2", help: "Show Overview", key: .hotkey("app.overview")) {
                    pages.toggleOverview()
                }
                .accessibilityIdentifier("sidebar.overview")
                SortMenu(page: page)
                newSpace
            }
            // A dropdown: its room opens at once and only the shelf slides, inside the clip. Moving the space list's
            // top over an animation left it scrolled a few points. It folds at once.
            VStack(spacing: 0) {
                if open {
                    shelf(others).transition(.move(edge: .top))
                }
            }
            .animation(open ? .slide : nil, value: open)
            .clipped()
        }
        .focusable(open)
        .focusEffectDisabled()
        .focused($focused)
        .focusSoon($focused, open)
        // A click elsewhere (a card, a row, another field) takes the keys, and the shelf folds.
        .onChange(of: focused) {
            if !focused, open {
                open = false
            }
        }
        .onMoveCommand { direction in
            let count = others.count + 1
            if direction == .down {
                lit = lit.map { min($0 + 1, count - 1) } ?? 0
            } else if direction == .up {
                lit = lit.map { max($0 - 1, 0) } ?? count - 1
            }
        }
        .onKeyPress(.return) {
            guard let lit else { return .ignored }
            if others.indices.contains(lit) {
                pick(others[lit])
            } else {
                openPanel()
            }
            return .handled
        }
        .onExitCommand { close() }
        // The overview hides the sidebar but keeps it, keys and all.
        .onChange(of: pages.overview) {
            if pages.overview {
                open = false
            }
        }
    }

    private var title: some View {
        Button {
            if open {
                close()
            } else {
                lit = nil
                open = true
            }
        } label: {
            HStack(spacing: 5) {
                Text(page.store.title).truncationMode(.middle).lineLimit(1)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.primary)
                Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary).opacity(open || over ? 1 : 0)
            }
            // A session change fades its name while the spaces slide.
            .animation(.fade, value: page.id)
            .padding(.horizontal, WorkspaceRow.textInset)
            .frame(height: 28)
        }
        .buttonStyle(ChromeStyle(radius: 7))
        .onHover { over = $0 }
        .contextMenu { SessionMenu(page: page, pages: pages, openSession: openSession) }
        .accessibilityLabel("Sessions")
        .accessibilityValue(page.store.title)
        .accessibilityIdentifier("sidebar.header")
    }

    private var newSpace: some View {
        IconButton(symbol: "plus", help: "New Space", key: .hotkey("space.new")) {
            Task { await page.newWorkspace() }
        }
        .disabled(page.store.state != .live)
        .accessibilityIdentifier("sidebar.new-workspace")
        .overlay {
            if plus, page.dragging != nil {
                DropIndicator(radius: 7)
            }
        }
        .onDrop(of: [.ovviDrag], delegate: PaneDrop(page: page, target: .move(.newWorkspace()), over: $plus))
        .clearsDrop(page) { plus = false }
    }

    private func shelf(_ others: [Page]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(others.enumerated()), id: \.element.id) { index, other in
                row(index, symbol: "rectangle.stack", other.store.title) { pick(other) }
                    .accessibilityIdentifier("sidebar.session.\(other.id)")
            }
            if !others.isEmpty {
                Rectangle().fill(.primary.opacity(0.14)).frame(height: 1).padding(4)
            }
            row(others.count, symbol: "plus.square.on.square", "Open Session…", key: Hotkeys.glyphs("session.open"),
                action: openPanel)
                .accessibilityIdentifier("sidebar.open-session")
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.14)))
        // As far under the header as the filter is under it.
        .padding(.top, 8)
    }

    private func row(_ index: Int, symbol: String, _ title: String, key: String = "",
                     action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
                Text(title).truncationMode(.middle).lineLimit(1)
                Spacer(minLength: 0)
                Text(key).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .frame(height: 28)
        }
        .buttonStyle(ChromeStyle(radius: 7, hovered: lit == index))
        .onHover { inside in
            if inside {
                lit = index
            } else if lit == index {
                lit = nil
            }
        }
        .accessibilityLabel(title)
    }

    private func pick(_ other: Page) {
        pages.show(other)
        close()
    }

    private func openPanel() {
        open = false
        openSession()
    }

    /// Folded by the keys or a pick: the keys go back to the page's card.
    private func close() {
        open = false
        pages.current?.focusKeyboardCard()
    }
}

/// Its own view: inside the header's body, each change there would make the menu again and close it.
private struct SortMenu: View {
    let page: Page
    private var settings = AppSettings()

    var body: some View {
        // `Page.spaceOrder`, read through the view's own settings so a change in Settings redraws the menu.
        let order = page.store.order ?? settings.spaceOrder
        Menu {
            Picker(
                "Sort Spaces",
                selection: Binding { order } set: { order in afterMenu { page.store.order = order } },
            ) {
                Text("Manual").tag(SpaceOrder.manual)
                Text("Recent").tag(SpaceOrder.recent)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            // As tall as the `+`'s glyph, which is shorter at the same size.
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ChromeStyle(radius: 7))
        .fixedSize()
        .tip("Sort Spaces")
        .accessibilityLabel("Sort Spaces")
        .accessibilityValue(order == .manual ? "Manual" : "Recent")
        .accessibilityIdentifier("sidebar.sort")
    }
}
