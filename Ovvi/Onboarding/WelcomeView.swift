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

    /// The picture's frame in the panel (`Welcome.size`); its corners are the filmed window's own, at the clips' scale.
    static let picture = CGRect(x: 24, y: 24, width: 912, height: 456)
    private static let frame = RoundedRectangle(cornerRadius: 12, style: .continuous)
    /// The clips show the app's whole 1280 x 640 pt window at this scale (scripts/record-onboarding.sh: 1824 x 912
    /// pixels).
    static let pictureScale: CGFloat = 0.7125
    /// Where the logo's panes go, back to front, as fractions of the first clip's frame (measured on its first
    /// frame): the window's sidebar and its two panes.
    private static let firstPanes = [CGRect(x: 0.0044, y: 0.0625, width: 0.2148, height: 0.932),
                                     CGRect(x: 0.2319, y: 0.0625, width: 0.3799, height: 0.932),
                                     CGRect(x: 0.6179, y: 0.0625, width: 0.381, height: 0.932)]

    private enum Page: String {
        case running, layout, agents, plugins, machines, herdr

        /// The picked words; the others the user may choose from are in the report (onboarding-v4.html).
        func words(herdrFound: Bool) -> (title: String, text: String) {
            switch self {
            case .running: ("Pick up where you left off", "Terminals, agents and tools run in sessions that keep "
                    + "going when you close the window or quit Ovvi.")
            case .layout: ("Split. Tab. Switch.", "⌘D splits a pane, ⌘T opens a tab, and each project gets its own "
                    + "space in the sidebar.")
            case .agents: ("TUI or chat, any time", "Switch seamlessly between an agent's terminal and its chat "
                    + "view. Orange needs you, blue is working, green is done.")
            case .plugins: ("Bring your tools in", "Git, Browser and File Explorer come built in. Write your own in "
                    + "TypeScript; you and agents open them with `ovvi`.")
            case .machines: ("Reach your other machines", "Add any machine you can ssh to. Its sessions get their own "
                    + "window and keep running while your Mac sleeps.")
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
            case .layout: 5
            case .agents: 4.2
            case .plugins: 6.5
            case .machines: 3.5
            case .herdr: 0
            }
        }
    }

    private var pages: [Page] {
        [.running, .layout, .agents, .plugins, .machines] + (herdrMissing ? [.herdr] : [])
    }

    private var still: Bool {
        Animation.reduced
    }

    var body: some View {
        let dark = colorScheme == .dark
        let look = Look(style: settings.style, dark: dark, contrast: colorSchemeContrast == .increased)
        let current = pages[page], last = page == pages.count - 1, shown = intro == nil
        let blocked = current == .herdr && !herdrFound
        let words = current.words(herdrFound: herdrFound)
        let playing = shown && current != .herdr ? clip(current, dark: dark) : nil
        VStack(spacing: 0) {
            picture(current, look: look, dark: dark).opacity(shown ? 1 : 0)
            // In one place, and never both at once: the old words go before the new ones come.
            ZStack {
                VStack(spacing: 6) {
                    Text(words.title).font(.system(size: 24, weight: .semibold))
                    Text(LocalizedStringKey(words.text)).font(.system(size: 15)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineSpacing(2).frame(maxWidth: 760)
                }
                .id(page * 2 + (herdrFound ? 1 : 0))
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.15)),
                                        removal: .opacity.animation(.easeIn(duration: 0.15))))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(shown ? 1 : 0)
            footer(last: last, blocked: blocked).opacity(shown ? 1 : 0)
        }
        .padding(Self.picture.minX)
        .background(WelcomeBackground())
        .overlay {
            if let intro {
                WelcomeIntro(step: intro, center: CGPoint(x: Welcome.size.width / 2, y: Welcome.size.height / 2 - 24),
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

    private func picture(_ page: Page, look: Look, dark: Bool) -> some View {
        let edge = look.edge(keyboard: false)
        return ZStack {
            if page == .herdr {
                HerdrStep(found: $herdrFound).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The test reads which look's clip shows (welcome.picture's value ends in dark or light).
                let player = reels.player(clip(page, dark: dark))
                WelcomeClip(player: player)
                    .accessibilityElement().accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("welcome.picture").accessibilityLabel(page.words(herdrFound: false).title)
                    .accessibilityValue(player == nil ? "missing" : "\(page.rawValue) \(dark ? "dark" : "light")")
            }
        }
        .id(page)
        .transition(still ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)),
                                                   removal: .opacity.combined(with: .scale(scale: 1.02))))
        .frame(width: Self.picture.width, height: Self.picture.height)
        .background(look.cardSolid())
        .clipShape(Self.frame)
        // A card's own edge: the rim inside, the stroke just outside.
        .overlay(Self.frame.strokeBorder(look.rim.all, lineWidth: 1))
        .overlay(Self.frame.inset(by: -edge.width / 2).stroke(edge.color, lineWidth: edge.width))
    }

    private func footer(last: Bool, blocked: Bool) -> some View {
        HStack(spacing: 8) {
            // The herdr step, last, waits for herdr: Skip still closes.
            if !last || blocked {
                Button("Skip", action: finish).buttonStyle(.plain).foregroundStyle(.secondary)
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
                    Capsule().fill(index == page ? Color.primary : Color.secondary.opacity(0.35))
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
        withAnimation(still ? .smooth(duration: 0.3) : .spring(duration: 0.55, bounce: 0.08)) {
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
        if !still {
            intro = .panes
            // The picture fades in as the panes settle into its own.
            try? await Task.sleep(for: .seconds(0.45))
        }
        endIntro()
    }

    private func endIntro() {
        guard intro != nil else { return }
        withAnimation(.smooth(duration: 0.55)) { intro = nil }
    }
}

private extension CGRect {
    /// A fraction of the picture's frame, in the panel's points.
    var inPicture: CGRect {
        let frame = WelcomeView.picture
        return CGRect(x: frame.minX + minX * frame.width, y: frame.minY + minY * frame.height,
                      width: width * frame.width, height: height * frame.height)
    }
}
