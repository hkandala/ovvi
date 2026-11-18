import HerdrKit
import SwiftUI

/// The page in view's header, over the pages: a session change slides only the spaces. Its title opens a shelf with the
/// window's sessions and Open Session.
struct SessionHeader: View {
    let pages: WindowPages
    let page: Page
    let openSession: () -> Void
    @State private var open = false
    /// Laid out while open and while it folds.
    @State private var shelved = false
    @State private var over = false
    @State private var plus = false
    /// The row under the pointer or the arrows: the sessions, then Open Session.
    @State private var lit: Int?
    @FocusState private var focused: Bool

    var body: some View {
        let list = pages.list
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
            // A dropdown that fades in as it slides: the filter and the spaces move down with it. Folded, it has no
            // height.
            Reveal(shown: open ? 1 : 0) {
                if shelved {
                    shelf(list).transition(.identity)
                }
            }
            .opacity(open ? 1 : 0)
            .clipped()
            // As it opens, its rows pass under the title: clicks and hover there stay the title's.
            .contentShape(.rect)
            .allowsHitTesting(open)
        }
        .focusable(open)
        .focusEffectDisabled()
        .focused($focused)
        .focusSoon($focused, open)
        .onMoveCommand { direction in
            let count = list.count + 1
            if direction == .down {
                lit = lit.map { min($0 + 1, count - 1) } ?? 0
            } else if direction == .up {
                lit = lit.map { max($0 - 1, 0) } ?? count - 1
            }
        }
        .onKeyPress(.return) {
            guard let lit, lit <= list.count else { return .ignored }
            if list.indices.contains(lit) {
                // The new page's card takes the keys, as after a click.
                self.lit = nil
                pages.show(list[lit])
            } else {
                openSession()
            }
            return .handled
        }
        .onExitCommand { fold() }
        // The overview hides the sidebar but keeps it, keys and all.
        .onChange(of: pages.overview) {
            if pages.overview {
                open = false
                shelved = false
            }
        }
        // The rows moved under the pointer, which gets no new hover: no row lit or showing Detach until it moves.
        .onChange(of: pages.list.count) { lit = nil }
    }

    private var title: some View {
        Button {
            if open {
                fold()
            } else {
                lit = nil
                shelved = true
                withAnimation(.slide) { open = true }
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

    private func shelf(_ list: [Page]) -> some View {
        VStack(spacing: 0) {
            // In the window's order, so a pick moves nothing: only the mark (a filled symbol, a bolder name) fades.
            ForEach(list.indices, id: \.self) { index in
                let other = list[index]
                let detach = pages.canDetach ? { pages.close(other) } : nil
                row(index, "sidebar.session.\(other.id)", symbol: "rectangle.stack", other.store.title,
                    current: other === page, detach: detach) { pages.show(other) }
            }
            Rectangle().fill(.primary.opacity(0.14)).frame(height: 1).padding(4)
            row(list.count, "sidebar.open-session", symbol: "plus.square.on.square", "Open Session…",
                key: Hotkeys.glyphs("session.open"), action: openSession)
        }
        .animation(.fade, value: page.id)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.14)))
        // As far from the header's glyphs as the filter is from its border.
        .padding(.vertical, 8)
    }

    private func row(_ index: Int, _ id: String, symbol: String, _ title: String, key: String = "",
                     current: Bool = false, detach: (() -> Void)? = nil,
                     action: @escaping () -> Void) -> some View
    {
        let detaches = detach != nil && lit == index
        return Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: current ? symbol + ".fill" : symbol).foregroundStyle(.secondary).frame(width: 18)
                Text(title).truncationMode(.middle).lineLimit(1).fontWeight(current ? .semibold : nil)
                Spacer(minLength: 0)
                Text(key).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(.leading, 4).padding(.trailing, detaches ? 22 : 4)
            .frame(height: 28)
        }
        .buttonStyle(ChromeStyle(radius: 6, hovered: lit == index))
        .accessibilityLabel(title)
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityActions {
            if let detach {
                Button("Detach Session", action: detach)
            }
        }
        .accessibilityIdentifier(id)
        .overlay(alignment: .trailing) {
            if let detach, detaches {
                IconButton(symbol: "rectangle.stack.badge.minus", help: "Detach Session", size: 18, action: detach)
                    // Its ink as far from the row's right edge as the row's symbol from its left.
                    .padding(.trailing, 3.5)
                    .accessibilityIdentifier(id + ".detach")
            }
        }
        .onHover { inside in
            if inside {
                lit = index
            } else if lit == index {
                lit = nil
            }
        }
    }

    /// Folded by the title or Esc, the keys go back to the page's card.
    private func fold() {
        withAnimation(.slide) { open = false } completion: {
            if !open {
                shelved = false
            }
        }
        pages.current?.focusKeyboardCard()
    }
}

/// Shows the shelf's lower part, from none to all of it, in whole points: a scroll view resized by a fraction of a
/// pixel keeps that fraction as its offset, so the space list under it would end scrolled.
private struct Reveal: Layout {
    var shown: Double

    var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        return CGSize(width: size.width, height: (size.height * shown).rounded())
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let shelf = subviews.first else { return }
        let size = ProposedViewSize(width: bounds.width, height: nil)
        shelf.place(at: CGPoint(x: bounds.minX, y: bounds.maxY - shelf.sizeThatFits(size).height), proposal: size)
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
