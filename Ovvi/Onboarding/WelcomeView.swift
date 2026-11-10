import SwiftUI

/// The welcome (ui/welcome): the logo draws itself and its pearl pane grows into one Ovvi window, which then builds
/// up over five pages; the herdr step last, only while This Mac has no herdr. Skip on every page, → ← Return and Esc;
/// a key or a click during the intro skips it.
struct WelcomeView: View {
    let herdrMissing: Bool
    let close: () -> Void
    @State private var page = 0
    @State private var intro = Intro.start
    /// The camera has moved in on what the page is about, once its pieces are in place.
    @State private var zoomed = false
    /// The scene's pictures up to this stage are drawn (`WelcomeScene.loaded`).
    @State private var loaded = 1
    @State private var herdrFound = false
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// The story's pages, the scene's stage each, then the herdr step.
    private static let story: [(title: String, words: String)] = [
        ("Meet Ovvi", "Your terminals, agents and the tools beside them, together in one Mac window. Everything runs "
            + "in a session, so it keeps going when you close the window or quit Ovvi. Come back, and it is all "
            + "where you left it."),
        ("One pane, then many", "You start with one pane. Split it to the right with **⌘D** or down with **⇧⌘D**, "
            + "and each new pane asks what it runs: a terminal, an agent, a browser, File Explorer or Git. Drag a "
            + "divider to resize."),
        ("Tabs and spaces", "When a task needs room of its own, open a tab with **⌘T**. Each tab shows what runs in "
            + "it. A space holds one project, with its folder, branch and tabs, and the sidebar lists your spaces "
            + "and their agents."),
        ("Agents and plugins", "Run Claude Code, Codex, Pi or OpenCode as a terminal or a chat: the same agent. "
            + "Orange needs you, blue works, green is done. Browser, Git and File Explorer come with Ovvi. New Plugin… "
            + "starts your own in TypeScript, and you or your agents open them with `ovvi`."),
        ("Any machine you can ssh to", "Add a machine, and its sessions open in a window of their own, with the "
            + "same panes, agents and plugins. Your SSH config works as it is, and work there keeps running while "
            + "your Mac sleeps."),
    ]

    private static let herdrWords = "herdr keeps your terminals and agents running in sessions, so they go on after "
        + "Ovvi quits. Ovvi installs it for you."

    private var reduceMotion: Bool {
        Animation.reduced
    }

    private var pages: Int {
        Self.story.count + (herdrMissing ? 1 : 0)
    }

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        let last = page == pages - 1, herdr = page == Self.story.count
        let blocked = herdr && !herdrFound, playing = intro < .scene
        ZStack(alignment: .topLeading) {
            // Under the scene: the back panes slide in under the pearl pane, which is the scene's first.
            MarkBack(intro: intro, reduceMotion: reduceMotion)
            // Reduce Motion: the intro and then each page's finished scene, zoomed in, cross-fade.
            WelcomeScene(stage: herdr ? 6 : page + 1, intro: intro,
                         zoomed: zoomed || reduceMotion && intro == .scene, loaded: loaded, reduceMotion: reduceMotion)
                .id(reduceMotion ? page * 2 + (intro == .scene ? 1 : 0) : 0)
                .transition(.opacity)
            if herdr {
                HerdrStep(found: $herdrFound)
                    .frame(width: WelcomeScene.view.width, height: WelcomeScene.view.height)
                    .padding(.leading, WelcomeScene.origin.x).padding(.top, WelcomeScene.origin.y)
                    .transition(.opacity)
            }
            if !playing {
                VStack(alignment: .leading, spacing: 0) {
                    words(herdr ? ("One more thing", Self.herdrWords) : Self.story[page])
                    Spacer(minLength: 0)
                    footer(last: last, blocked: blocked)
                }
                .padding(.horizontal, WelcomeScene.origin.x)
                .padding(.top, WelcomeScene.view.maxY + 26)
                .padding(.bottom, 24)
                .frame(width: Welcome.size.width, height: Welcome.size.height)
                .transition(.opacity)
            }
        }
        .frame(width: Welcome.size.width, height: Welcome.size.height, alignment: .topLeading)
        .background(WelcomeBackground())
        .overlay {
            // The intro: a click anywhere skips it.
            if playing {
                Color.clear.contentShape(.rect).onTapGesture(perform: skipIntro)
            }
        }
        // → turns the page as Next does; Esc on the last page closes as Get Started. During the intro → and Return
        // skip it, and Esc closes the welcome.
        .background {
            Group {
                Button("Next", action: next).keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(!playing && (last || blocked))
                Button("Skip Intro", action: skipIntro).keyboardShortcut(.defaultAction).disabled(!playing)
                Button("Close", action: close).keyboardShortcut(.cancelAction)
                    .disabled(!playing && (!last || blocked))
            }
            .opacity(0).accessibilityHidden(true)
        }
        .environment(\.look, look)
        .task { await play() }
        // The camera moves in once the page's pieces are in place and the whole window has shown for a moment.
        .task(id: "\(page) \(intro)") {
            guard intro == .scene, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(page == 0 ? 2.2 : 1.9))
            guard !Task.isCancelled else { return }
            zoomed = true
            // Then the next page's pictures, once the zoom is done.
            try? await Task.sleep(for: .seconds(1.3))
            loaded = max(loaded, page + 2)
        }
    }

    private func words(_ page: (title: String, words: String)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(page.title).font(.system(size: 24, weight: .semibold))
            Text(LocalizedStringKey(page.words)).font(.system(size: 15)).foregroundStyle(.secondary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 660, alignment: .leading)
        .id(page.title)
        .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 4)))
    }

    private func footer(last: Bool, blocked: Bool) -> some View {
        HStack(spacing: 10) {
            // On the herdr step too, while Next waits for herdr.
            if !last || blocked {
                Button("Skip", action: close).buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction).accessibilityIdentifier("welcome.skip")
            }
            Spacer()
            if page > 0 {
                Button("Back") { go(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                    .accessibilityIdentifier("welcome.back")
            }
            Button(last ? "Get Started" : "Next", action: next)
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(blocked)
                .accessibilityIdentifier("welcome.next")
        }
        .controlSize(.large)
        .overlay {
            HStack(spacing: 6) {
                ForEach(0 ..< pages, id: \.self) { index in
                    Capsule().fill(index == page ? Color.primary.opacity(0.75) : Color.primary.opacity(0.2))
                        .frame(width: index == page ? 16 : 6, height: 6)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: page)
            .accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityIdentifier("welcome.dots")
            .accessibilityValue("\(page + 1) of \(pages)")
        }
    }

    /// The intro's beats; Reduce Motion: the whole mark fades in, then the scene.
    private func play() async {
        let beats: [(Intro, Double)] = reduceMotion ? [(.fill, 0.1), (.scene, 1.6)]
            : [(.outline, 0.15), (.fill, 0.8), (.name, 1.05), (.scene, 2.1)]
        var now = 0.0
        for (step, time) in beats {
            try? await Task.sleep(for: .seconds(time - now))
            now = time
            guard intro < step else { return }
            withAnimation(.default) { intro = step }
        }
    }

    /// Read when pressed: SwiftUI keeps a key's first closure, so what it captured would be stale.
    private func next() {
        if intro < .scene {
            skipIntro()
        } else if page == pages - 1 {
            close()
        } else {
            go(1)
        }
    }

    private func skipIntro() {
        withAnimation(.default) { intro = .scene }
    }

    private func go(_ step: Int) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.4) : .smooth(duration: 0.35)) {
            zoomed = false
            page = min(max(page + step, 0), pages - 1)
        }
    }
}
