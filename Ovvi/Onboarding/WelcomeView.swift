import SwiftUI

/// The welcome (ui/welcome): the icon and the name settle in, the icon glides into the corner, then the pages, one
/// topic each, a picture on top and the words below; the herdr step last, only while This Mac has no herdr. Skip on
/// every page, → ← Return and Esc; a key or a click during the intro goes straight to the first page.
struct WelcomeView: View {
    let herdrMissing: Bool
    let close: () -> Void
    @State private var page = 0
    /// +1 forward, -1 back: the side a page slides in from.
    @State private var direction = 1
    @State private var intro = Intro.start
    @State private var pictures = WelcomePictures()
    @State private var herdrFound = false
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var reduceMotion: Bool {
        Animation.reduced
    }

    private static let pad: CGFloat = 20
    private static let iconSize: CGFloat = 128, markSize: CGFloat = 24

    private enum Intro {
        /// The icon small and blurred, the name loose and low; then settled; then the pages.
        case start, settled, done
    }

    /// The tour's pages, then the herdr step (nil) while This Mac has no herdr.
    private var pages: [WelcomePage?] {
        WelcomePage.all + (herdrMissing ? [nil] : [])
    }

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        let done = intro == .done
        ZStack(alignment: .topLeading) {
            if done {
                VStack(spacing: 0) {
                    header.padding(.bottom, 8)
                    content.frame(maxHeight: .infinity, alignment: .top)
                    footer
                }
                .padding(Self.pad)
                .transition(.opacity.animation(.easeOut(duration: 0.45).delay(0.25)))
            }
            logo
        }
        .background(WelcomeBackground())
        .overlay {
            if !done {
                Color.clear.contentShape(.rect).onTapGesture(perform: finishIntro)
            }
        }
        .background { keys }
        .environment(\.look, look)
        .task { await playIntro() }
        .task(id: "\(page) \(colorScheme)") { await pictures.keep(names(around: page)) }
    }

    /// The app's icon and its name: in the middle while the intro plays, then the icon alone as the corner's mark.
    /// Reduce Motion: they only fade, and the mark fades in at the corner.
    private var logo: some View {
        let done = intro == .done, settled = intro != .start || reduceMotion
        let middle = CGPoint(x: Welcome.size.width / 2, y: Welcome.size.height / 2 - 30)
        let corner = CGPoint(x: Self.pad + Self.markSize / 2, y: Self.pad + 12)
        return ZStack {
            if reduceMotion {
                icon(Self.iconSize).position(middle).opacity(intro == .settled ? 1 : 0)
                icon(Self.markSize).position(corner).opacity(done ? 1 : 0)
            } else {
                icon(done ? Self.markSize : Self.iconSize)
                    .scaleEffect(settled ? 1 : 0.92).blur(radius: settled ? 0 : 12).opacity(settled ? 1 : 0)
                    .position(done ? corner : middle)
            }
            Text("Ovvi").font(.system(size: 34, weight: .semibold))
                .modifier(Tracking(value: settled ? 0.4 : 9))
                .opacity(intro == .settled ? 1 : 0).offset(y: settled ? 0 : 8)
                .position(x: Welcome.size.width / 2, y: Welcome.size.height / 2 + 66)
                .accessibilityHidden(true)
        }
        .frame(width: Welcome.size.width, height: Welcome.size.height)
        .allowsHitTesting(false)
    }

    private func icon(_ size: CGFloat) -> some View {
        Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// Skip on every page but the last, and on the herdr step until herdr is found (a failed install).
    private var header: some View {
        HStack {
            Spacer()
            if page < pages.count - 1 || blocked {
                Button("Skip", action: close).buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityIdentifier("welcome.skip")
            }
        }
        .frame(height: 24)
    }

    private var content: some View {
        Group {
            if let shown = pages[page] {
                PageView(page: shown, pictures: pictures, still: reduceMotion)
            } else {
                HerdrStep(found: $herdrFound)
            }
        }
        .id(page)
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 18 * CGFloat(direction))),
            // A removal reads the page's last render, the step before: the old page only fades.
            removal: .opacity,
        ))
    }

    private var footer: some View {
        let last = page == pages.count - 1
        return ZStack {
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule().fill(index == page ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: index == page ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityIdentifier("welcome.dots")
            .accessibilityValue("\(page + 1) of \(pages.count)")
            HStack {
                if page > 0 {
                    Button("Back") { go(-1) }.buttonStyle(.glass).keyboardShortcut(.leftArrow, modifiers: [])
                        .accessibilityIdentifier("welcome.back")
                }
                Spacer()
                Button(last ? "Get Started" : "Next") { page == pages.count - 1 ? close() : go(1) }
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(blocked)
                    .accessibilityIdentifier("welcome.next")
            }
        }
        .controlSize(.large)
    }

    /// → turns the page as Next does; Esc closes it from any page and the intro, as Skip (Get Started on the last).
    /// During the intro → and Return go to the first page.
    private var keys: some View {
        let done = intro == .done, last = page == pages.count - 1
        return Group {
            Button("Next") { intro == .done ? go(1) : finishIntro() }.keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(done && (last || blocked))
            Button("Start") { finishIntro() }.keyboardShortcut(.defaultAction).disabled(done)
            Button("Close", action: close).keyboardShortcut(.cancelAction)
        }
        .opacity(0).accessibilityHidden(true)
    }

    private var blocked: Bool {
        pages[page] == nil && !herdrFound
    }

    private func go(_ step: Int) {
        direction = step
        withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.5, bounce: 0)) {
            page = min(max(page + step, 0), pages.count - 1)
        }
    }

    /// The icon settles from small and soft, the name rises under it as its letters close up; then the icon glides
    /// up into the corner as the first page fades in. Reduce Motion: a plain fade.
    private func playIntro() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.5)) { intro = .settled }
            try? await Task.sleep(for: .seconds(1.4))
        } else {
            withAnimation(.spring(duration: 1.1, bounce: 0)) { intro = .settled }
            try? await Task.sleep(for: .seconds(1.7))
        }
        finishIntro()
    }

    private func finishIntro() {
        guard intro != .done else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.4) : .spring(duration: 0.8, bounce: 0.08)) {
            intro = .done
        }
    }

    /// The pictures of the page in view and the next, in this appearance.
    private func names(around page: Int) -> Set<String> {
        let look = colorScheme == .dark ? "-dark" : "-light"
        return Set([page - 1, page, page + 1].filter { pages.indices.contains($0) }
            .flatMap { pages[$0]?.shots.map { $0.picture + look } ?? [] })
    }
}

/// A page: its picture, then its title and words, which rise 6 pt into place.
private struct PageView: View {
    let page: WelcomePage
    let pictures: WelcomePictures
    let still: Bool
    @State private var risen = false
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WelcomePicture(shots: page.shots, pictures: pictures, still: still)
            VStack(alignment: .leading, spacing: 7) {
                Text(page.title).font(.system(size: 22, weight: .semibold))
                page.words(look).font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(3)
                    .textRenderer(KeycapText(fill: look.paletteField, rim: look.divider))
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 820, alignment: .leading)
            }
            .padding(.horizontal, 6).padding(.top, 16)
            .opacity(risen ? 1 : 0).offset(y: risen || still ? 0 : 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.15)) { risen = true }
        }
    }
}

/// Letter spacing that animates.
private struct Tracking: ViewModifier, Animatable {
    var value: CGFloat

    var animatableData: CGFloat {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        content.tracking(value)
    }
}
