import SwiftUI

/// The welcome (ui/welcome): the mark deals its three panes in, "Ovvi" fades in, and the mark moves up into the corner
/// as the first page's pictures rise. Four pages of close-ups, then the herdr step only while This Mac has no herdr.
/// Skip on every page; → ← Return and Esc; a click or a key during the intro goes straight to the first page.
struct WelcomeView: View {
    let herdrMissing: Bool
    let close: () -> Void
    @State private var page = 0
    @State private var forward = true
    @State private var intro = true
    /// How many of the mark's panes stand in the stack; -1 before its tile shows.
    @State private var placed = -1
    @State private var named = false
    @State private var herdrFound = false
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private static let inset = (side: 36.0, top: 24.0, bottom: 28.0)

    private var still: Bool {
        Animation.reduced
    }

    private var pages: [WelcomePage] {
        [.hello, .panes, .agents, .machines] + (herdrMissing ? [.herdr] : [])
    }

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        let last = page == pages.count - 1
        let blocked = pages[page] == .herdr && !herdrFound
        // Skip shows until the last page can close with Get Started (the herdr step waits for herdr).
        let skips = !last || blocked
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    // In once the mark has landed beside it.
                    Text("Ovvi").font(.system(size: 15, weight: .semibold)).padding(.leading, 30)
                        .opacity(intro ? 0 : 1).animation(.easeOut(duration: 0.3).delay(still ? 0 : 0.4), value: intro)
                    Spacer()
                    if skips {
                        Button("Skip", action: close).buttonStyle(.plain).foregroundStyle(.secondary)
                            .keyboardShortcut(.cancelAction).accessibilityIdentifier("welcome.skip")
                    }
                }
                .frame(height: 22)
                ZStack {
                    if !intro {
                        WelcomePageView(page: pages[page], forward: forward, still: still, herdrFound: $herdrFound)
                            .id(page)
                            // The leaving page clears quickly, before the new one's pictures rise in its place.
                            .transition(.asymmetric(insertion: .identity, removal: (still ? AnyTransition.opacity
                                    : .offset(x: forward ? -48 : 48).combined(with: .opacity))
                                .animation(.easeIn(duration: 0.22))))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer(last: last, blocked: blocked).opacity(intro ? 0 : 1).accessibilityHidden(intro)
            }
            .padding(.horizontal, Self.inset.side).padding(.top, Self.inset.top).padding(.bottom, Self.inset.bottom)
            if intro {
                let moves = named || still
                Text("Ovvi").font(.system(size: 38, weight: .semibold)).tracking(-0.4)
                    .opacity(named ? 1 : 0).offset(y: moves ? 0 : 8).blur(radius: moves ? 0 : 6)
                    .frame(width: Welcome.size.width).offset(y: 370)
                    .transition(still ? .opacity : .opacity.combined(with: .offset(y: -10)))
                    .accessibilityIdentifier("welcome.intro")
                // The first page's picture, drawn unseen during the intro so it is decoded before the page comes in.
                Image("welcome/hero").resizable().frame(width: 2, height: 1).opacity(0.01).accessibilityHidden(true)
            }
            let center = CGPoint(x: Welcome.size.width / 2, y: 280)
            let corner = CGPoint(x: Self.inset.side + 11, y: Self.inset.top + 11)
            if still {
                OvviMark(size: 112).shadow(color: look.floatShadow, radius: 18, y: 8).position(center)
                    .opacity(intro && named ? 1 : 0)
                OvviMark(size: 22).position(corner).opacity(intro ? 0 : 1)
            } else {
                OvviMark(size: 112, placed: placed)
                    .shadow(color: look.floatShadow, radius: intro ? 18 : 4, y: intro ? 8 : 1)
                    .scaleEffect(intro ? 1 : 22 / 112)
                    .position(intro ? center : corner)
            }
        }
        .background(WelcomeBackground())
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { endIntro() }, including: intro ? .all : .subviews)
        // → turns the page as Next does; Esc without Skip closes it as Get Started.
        .background {
            Group {
                Button("Next") { go(1) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(last || blocked)
                Button("Close", action: close).keyboardShortcut(.cancelAction).disabled(skips)
            }
            .opacity(0).accessibilityHidden(true)
        }
        .environment(\.look, look)
        .task { await playIntro() }
    }

    private func footer(last: Bool, blocked: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule().fill(index == page ? Color.primary.opacity(0.85) : Color.primary.opacity(0.18))
                        .frame(width: index == page ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityIdentifier("welcome.dots")
            .accessibilityValue("\(page + 1) of \(pages.count)")
            Spacer()
            if page > 0 {
                Button("Back") { go(-1) }.buttonStyle(.glass).keyboardShortcut(.leftArrow, modifiers: [])
                    .accessibilityIdentifier("welcome.back")
            }
            Button(last ? "Get Started" : "Next") { last ? close() : go(1) }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(blocked)
                .accessibilityIdentifier("welcome.next")
        }
        .controlSize(.large)
    }

    /// The mark's tile, its panes one by one (charcoal, gray, pearl), the name, then the mark to the corner and the
    /// first page.
    private func playIntro() async {
        if still {
            withAnimation(.easeOut(duration: 0.4)) { named = true }
        } else {
            for pane in 0 ... 3 {
                guard await pause([0.1, 0.3, 0.14, 0.14][pane]) else { return }
                withAnimation(.spring(duration: 0.55, bounce: pane == 0 ? 0.15 : 0.3)) { placed = pane }
            }
            guard await pause(0.4) else { return }
            withAnimation(.easeOut(duration: 0.5)) { named = true }
        }
        // `-welcomeHold <seconds>`: a test holds the intro until its key.
        let hold = UserDefaults.standard.double(forKey: "welcomeHold")
        guard await pause(hold > 0 ? hold : still ? 1.6 : 0.95) else { return }
        endIntro()
    }

    /// False once the intro was cut short (a click, a key) or the panel closed.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return intro && !Task.isCancelled
    }

    private func endIntro() {
        guard intro else { return }
        withAnimation(still ? .easeInOut(duration: 0.35) : .spring(duration: 0.75, bounce: 0.18)) {
            placed = 3
            named = true
            intro = false
        }
    }

    /// Turns the page; during the intro Next or → only ends it.
    private func go(_ step: Int) {
        guard !intro else { return endIntro() }
        // The leaving page takes its slide from `forward`, so it is set in an update before the turn.
        forward = step > 0
        let turn: Animation = still ? .easeInOut(duration: 0.3) : .spring(duration: 0.5, bounce: 0.12)
        Task { @MainActor in
            withAnimation(turn) { page = min(max(page + step, 0), pages.count - 1) }
        }
    }
}
