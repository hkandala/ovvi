import AVFoundation
import SwiftUI

/// The welcome (ui/welcome): the intro, then five pages, each a short looping clip of the app with a title and one
/// sentence, and the herdr step last while This Mac has no herdr. Skip on every page, → ← Return and Esc.
struct WelcomeView: View {
    let herdrMissing: Bool
    let close: () -> Void
    @State private var page = 0
    /// nil once the intro has handed over to the first page.
    @State private var intro: WelcomeIntro.Step? = .hidden
    @State private var herdrFound = false
    @State private var reels = WelcomeClip.Reels()
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// The clips show the app's whole 1200 x 800 pt window at this scale (scripts/record-onboarding.sh: 1920 x 1280
    /// pixels).
    static let pictureScale: CGFloat = 0.8
    /// Where the logo's panes go, back to front, as fractions of the first clip's frame (measured on its first
    /// frame): the window's sidebar and its two panes.
    private static let firstPanes = [CGRect(x: 0.0073, y: 0.0563, width: 0.2375, height: 0.9336),
                                     CGRect(x: 0.25, y: 0.0563, width: 0.3381, height: 0.9336),
                                     CGRect(x: 0.5955, y: 0.0563, width: 0.3977, height: 0.9336)]

    private enum Page: String {
        case running, layout, agents, plugins, machines, herdr

        @MainActor func words(herdrFound: Bool) -> (title: String, text: String) {
            switch self {
            case .running: ("Your work keeps running", "Terminals, agents and tools live in sessions. Close the window "
                    + "or quit Ovvi, and they keep going.")
            case .layout: ("Panes, tabs and spaces", "Split a pane with \(Hotkeys.named("pane.split-right")), open a "
                    + "tab with \(Hotkeys.named("tab.new")), and keep each project in its own space.")
            case .agents: ("Work with agents your way", "Watch an agent in its terminal, then switch to the chat when "
                    + "it suits you: the same agent, mid-task.")
            case .plugins: ("Everything you need, right there", "Open Git, a browser or your own plugins beside any "
                    + "pane, or let your agent open them.")
            case .machines: ("Remote, without the hassle", "Any machine you can ssh to: the same panes and agents, "
                    + "still running while your Mac sleeps.")
            case .herdr where herdrFound: ("You're all set", "Your sessions will keep running from here on. Get "
                    + "Started, and open a folder or a session.")
            case .herdr: ("One more thing: herdr", "It keeps your sessions running in the background, so nothing "
                    + "stops when you close the window.")
            }
        }

        /// Reduce Motion: the clip's frame where its change shows (scripts/record-onboarding.sh), still.
        var still: Double {
            switch self {
            case .running: 4.5
            case .layout: 4.5
            case .agents: 5
            case .plugins: 13
            case .machines: 8
            case .herdr: 0
            }
        }
    }

    private var pages: [Page] {
        [.running, .layout, .agents, .plugins, .machines] + (herdrMissing ? [.herdr] : [])
    }

    /// The clips are the pages' content: they play with Animations off, and only Reduce Motion stills them.
    private var still: Bool {
        Animation.reduceMotion
    }

    var body: some View {
        let dark = colorScheme == .dark
        let look = Look(style: settings.style, dark: dark, contrast: colorSchemeContrast == .increased)
        let current = pages[page], last = page == pages.count - 1, shown = intro == nil
        let blocked = current == .herdr && !herdrFound
        let words = current.words(herdrFound: herdrFound)
        let playing = shown && current != .herdr ? clip(current, dark: dark) : nil
        // The clip fills the panel; the words and buttons sit over its foot, on a shade that keeps them legible.
        ZStack(alignment: .bottom) {
            picture(current, dark: dark).opacity(shown ? 1 : 0)
            // Dark at the edge, fading out above the title; a soft glow keeps the words legible.
            if current != .herdr {
                LinearGradient(stops: [.init(color: Look.shade(dark).opacity(0), location: 0),
                                       .init(color: Look.shade(dark).opacity(0.5), location: 0.35),
                                       .init(color: Look.shade(dark), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 180).allowsHitTesting(false).opacity(shown ? 1 : 0).transition(.opacity)
            }
            VStack(spacing: 22) {
                // In one place, and never both at once: the old words go before the new ones come.
                ZStack {
                    VStack(spacing: 6) {
                        Text(words.title).font(.system(size: 26, weight: .semibold))
                        Text(LocalizedStringKey(words.text)).font(.system(size: 15))
                            .multilineTextAlignment(.center).lineSpacing(2).frame(maxWidth: 680)
                    }
                    .shadow(color: current == .herdr ? .clear : Look.shade(dark).opacity(0.7), radius: 8)
                    .id(page * 2 + (herdrFound ? 1 : 0))
                    .transition(.asymmetric(insertion: .opacity.animation(.motion(.easeOut(duration: 0.3).delay(0.15))),
                                            removal: .opacity.animation(.motion(.easeIn(duration: 0.15)))))
                }
                footer(last: last, blocked: blocked)
            }
            .padding(.horizontal, 28).padding(.bottom, 24)
            .opacity(shown ? 1 : 0)
        }
        .frame(width: Welcome.size.width, height: Welcome.size.height)
        .background(WelcomeBackground())
        .clipShape(WelcomeBackground.shape)
        .overlay {
            if let intro {
                WelcomeIntro(step: intro, center: CGPoint(x: Welcome.size.width / 2, y: Welcome.size.height / 2 - 30),
                             panes: Self.firstPanes.map(\.inPicture))
                    .transition(.opacity)
            }
        }
        // → turns the page as Next does; Esc on the last page closes it as Get Started.
        .background {
            Group {
                Button("Next") { go(1) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(last || blocked)
                Button("Close", action: finish).keyboardShortcut(.cancelAction).disabled(!last || blocked)
            }
            .opacity(0).accessibilityHidden(true)
        }
        // A click during the intro goes straight to the first page.
        .simultaneousGesture(TapGesture().onEnded { endIntro() }, isEnabled: !shown)
        .environment(\.look, look)
        .onChange(of: playing, initial: true) { reels.show(playing, at: still ? current.still : nil) }
        // The other pages' clips load once the intro has played (the page in view loads its own at once): their
        // first frames are ready before their pages show, and the intro's frames have the main thread.
        .task(id: dark) {
            try? await Task.sleep(for: .seconds(2.5))
            for page in pages where page != .herdr {
                _ = reels.player(clip(page, dark: dark))
            }
        }
        .task { await playIntro() }
    }

    private func picture(_ page: Page, dark: Bool) -> some View {
        ZStack {
            if page == .herdr {
                HerdrStep(found: $herdrFound).padding(.bottom, 170)
            } else {
                // The test reads which look's clip shows (welcome.picture's value ends in dark or light).
                let player = reels.player(clip(page, dark: dark))
                WelcomeClip(player: player)
                    .accessibilityElement().accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("welcome.picture").accessibilityLabel(page.words(herdrFound: false).title)
                    .accessibilityValue(player == nil ? "missing" : "\(page.rawValue) \(dark ? "dark" : "light")")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(page)
        // Over the whole panel: it comes in from a touch larger, never showing an edge.
        .transition(still ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.03)),
                                                   removal: .opacity))
    }

    private func footer(last: Bool, blocked: Bool) -> some View {
        HStack(spacing: 8) {
            // The herdr step, last, waits for herdr: Skip still closes.
            if !last || blocked {
                Button("Skip", action: finish).buttonStyle(.plain).foregroundStyle(.primary.opacity(0.75))
                    .keyboardShortcut(.cancelAction).accessibilityIdentifier("welcome.skip")
            }
            Spacer()
            if page > 0 {
                Button("Back") { go(-1) }.buttonStyle(.glass).keyboardShortcut(.leftArrow, modifiers: [])
                    .accessibilityIdentifier("welcome.back")
            }
            Button(last ? "Get Started" : "Next") { last ? finish() : go(1) }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(blocked)
                .accessibilityIdentifier("welcome.next")
        }
        .controlSize(.large)
        .overlay {
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule().fill(Color.primary.opacity(index == page ? 0.9 : 0.35))
                        .frame(width: index == page ? 16 : 6, height: 6)
                }
            }
            .accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityIdentifier("welcome.dots")
            .accessibilityValue("\(page + 1) of \(pages.count)")
        }
    }

    private func clip(_ page: Page, dark: Bool) -> String {
        "welcome-\(page.rawValue)-\(dark ? "dark" : "light")"
    }

    /// The players stop before the panel goes.
    private func finish() {
        reels.show(nil, at: nil)
        close()
    }

    /// A key during the intro only ends it: the first page shows.
    private func go(_ step: Int) {
        guard intro == nil else { return endIntro() }
        withAnimation(.motion(still ? .smooth(duration: 0.3) : .spring(duration: 0.55, bounce: 0.08))) {
            page = min(max(page + step, 0), pages.count - 1)
        }
    }

    /// The logo, then (with motion) its panes spread into the first picture's, which fades in over them.
    private func playIntro() async {
        try? await Task.sleep(for: .seconds(0.15))
        guard intro == .hidden else { return }
        intro = .mark
        try? await Task.sleep(for: .seconds(1.2))
        guard intro != nil else { return }
        if !Animation.reduced {
            intro = .panes
            // The picture fades in as the panes settle into its own.
            try? await Task.sleep(for: .seconds(0.45))
        }
        endIntro()
    }

    private func endIntro() {
        guard intro != nil else { return }
        withAnimation(.motion(.smooth(duration: 0.55))) { intro = nil }
    }
}

private extension CGRect {
    /// A fraction of the picture, in the panel's points: the clips fill the panel (`Welcome.size`).
    var inPicture: CGRect {
        let size = Welcome.size
        return CGRect(x: minX * size.width, y: minY * size.height, width: width * size.width,
                      height: height * size.height)
    }
}
