import SwiftUI

/// The welcome (ui/welcome): the intro, then an annotated tour of one window, and last the herdr step while This Mac
/// has no herdr. Skip or Esc on every page; → ← Return; a key or a click during the intro goes to the first page.
struct WelcomeView: View {
    let herdrMissing: Bool
    let close: () -> Void
    @State private var page = 0
    @State private var intro = true
    /// The page whose callouts show: set once the camera has reached it.
    @State private var drawn: Int?
    @State private var herdrFound = false
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var reduceMotion: Bool {
        Animation.reduced
    }

    private var pages: [Tour.Page] {
        Tour.pages + (herdrMissing ? [Tour.herdr] : [])
    }

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        let pages = pages, shown = pages[page], last = page == pages.count - 1
        let blocked = shown.shot == nil && !herdrFound
        // The herdr step has no shot: the last one stays framed, hidden, so Back pans from there.
        let framed = shown.shot == nil ? Tour.pages[Tour.pages.count - 1] : shown
        VStack(spacing: 0) {
            ZStack {
                look.track
                TourPicture(focus: intro ? Self.closer(framed.focus) : framed.focus, shot: framed.shot ?? "",
                            callouts: framed.callouts, drawn: drawn == page && shown.shot != nil,
                            reduceMotion: reduceMotion)
                    .opacity(shown.shot == nil ? 0 : 1)
                    .id(reduceMotion ? page : 0)
                    .transition(.opacity)
                if shown.shot == nil {
                    HerdrStep(found: $herdrFound).transition(.opacity)
                }
            }
            .frame(width: Tour.picture.width, height: Tour.picture.height)
            .overlay(alignment: .bottom) { Rectangle().fill(look.divider).frame(height: 0.5) }
            VStack(alignment: .leading, spacing: 6) {
                Text(shown.title).font(.system(size: 22, weight: .semibold))
                Text(shown.text).font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(page)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            .padding(.horizontal, 32).padding(.top, 20)
            Spacer(minLength: 0)
            // Not there for keys or tests during the intro: its keys go to the first page.
            footer(pages.count, last: last, blocked: blocked)
                .padding(.horizontal, 24).padding(.bottom, 20)
                .disabled(intro).accessibilityHidden(intro)
        }
        .opacity(intro ? 0 : 1)
        .overlay {
            if intro {
                WelcomeIntro(reduceMotion: reduceMotion) { endIntro() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(.rect)
                    .onTapGesture { endIntro() }
                    .accessibilityElement().accessibilityIdentifier("welcome.intro")
                    .transition(.opacity)
            }
        }
        .background(WelcomeBackground())
        .clipShape(WelcomeBackground.shape)
        // → turns the page as Next does; Esc on the last page closes it as Get Started. During the intro Return, → and
        // Space go to the first page, and Esc skips the welcome.
        .background {
            Group {
                if intro {
                    Button("Begin") { endIntro() }.keyboardShortcut(.defaultAction)
                    Button("Begin") { endIntro() }.keyboardShortcut(.rightArrow, modifiers: [])
                    Button("Begin") { endIntro() }.keyboardShortcut(.space, modifiers: [])
                    Button("Skip", action: close).keyboardShortcut(.cancelAction)
                } else {
                    Button("Next") { go(1) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(last || blocked)
                    Button("Close", action: close).keyboardShortcut(.cancelAction).disabled(!last || blocked)
                }
            }
            .opacity(0).accessibilityHidden(true)
        }
        .environment(\.look, look)
    }

    private func footer(_ count: Int, last: Bool, blocked: Bool) -> some View {
        HStack(spacing: 10) {
            if !last || blocked {
                Button("Skip", action: close).buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction).accessibilityIdentifier("welcome.skip")
            }
            Spacer()
            if page > 0 {
                Button("Back") { go(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                    .accessibilityIdentifier("welcome.back")
            }
            Button(last ? "Get Started" : "Next") { last ? close() : go(1) }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(blocked)
                .accessibilityIdentifier("welcome.next")
        }
        .controlSize(.large)
        .overlay {
            HStack(spacing: 6) {
                ForEach(0 ..< count, id: \.self) { index in
                    Capsule().fill(index == page ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: index == page ? 16 : 6, height: 6)
                }
            }
            .accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityIdentifier("welcome.dots")
            .accessibilityValue("\(page + 1) of \(count)")
        }
    }

    /// The first page's frame as the intro dissolves into it: a little closer, so the window settles into place.
    private static func closer(_ focus: CGRect) -> CGRect {
        focus.insetBy(dx: focus.width * 0.05, dy: focus.height * 0.05)
    }

    private func endIntro() {
        guard intro else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.4) : .spring(duration: 0.9, bounce: 0)) { intro = false }
        draw(after: reduceMotion ? 0.3 : 0.6)
    }

    private func go(_ step: Int) {
        let next = min(max(page + step, 0), pages.count - 1)
        guard next != page else { return }
        drawn = nil
        withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .spring(duration: 0.8, bounce: 0.06)) { page = next }
        draw(after: reduceMotion ? 0.2 : 0.62)
    }

    /// Draws the page's callouts once the camera is (nearly) there, unless the page turned again meanwhile.
    private func draw(after seconds: Double) {
        let target = page
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if page == target, !intro {
                drawn = target
            }
        }
    }
}
