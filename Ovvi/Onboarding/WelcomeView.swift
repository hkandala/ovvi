import SwiftUI

/// The welcome's pages, the herdr step only while This Mac has no herdr; Skip on every page, → ← Return and Esc.
struct WelcomeView: View {
    let herdrMissing: Bool
    let close: () -> Void
    @State private var page = 0
    @State private var herdrFound = false
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private enum Page {
        case hello, herdr, end
    }

    private var pages: [Page] {
        [.hello] + (herdrMissing ? [.herdr] : []) + [.end]
    }

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        let last = page == pages.count - 1
        let blocked = pages[page] == .herdr && !herdrFound
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if !last {
                    Button("Skip", action: close).buttonStyle(.plain).foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction).accessibilityIdentifier("welcome.skip")
                }
            }
            .frame(height: 20)
            Group {
                switch pages[page] {
                case .hello:
                    VStack(spacing: 24) {
                        // The pictures come in a dark and a light set, the one of the app's appearance.
                        RoundedRectangle(cornerRadius: 12).fill(look.cardFill).frame(width: 480, height: 300)
                            .accessibilityElement().accessibilityAddTraits(.isStaticText)
                            .accessibilityIdentifier("welcome.picture")
                            .accessibilityValue("placeholder \(colorScheme == .dark ? "dark" : "light")")
                        text("Welcome to Ovvi", "Your terminals, agents and tools, in one Mac window.")
                    }
                case .herdr: HerdrStep(found: $herdrFound)
                case .end: text("You're all set", "Open a folder or a session to begin.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(page)
            .transition(.opacity)
            HStack {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle().fill(index == page ? Color.primary : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityIdentifier("welcome.dots")
                .accessibilityValue("\(page + 1) of \(pages.count)")
                Spacer()
                if page > 0 {
                    Button("Back") { go(-1) }.accessibilityIdentifier("welcome.back")
                }
                Button(last ? "Get Started" : "Next") { last ? close() : go(1) }
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction).disabled(blocked)
                    .accessibilityIdentifier("welcome.next")
            }
            .controlSize(.large)
        }
        .padding(24)
        .background(WelcomeBackground())
        // → and ← turn the pages as Next and Back do; Esc on the last page closes it as Get Started.
        .background {
            Group {
                Button("Next") { go(1) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(last || blocked)
                Button("Back") { go(-1) }.keyboardShortcut(.leftArrow, modifiers: []).disabled(page == 0)
                Button("Close", action: close).keyboardShortcut(.cancelAction).disabled(!last)
            }
            .opacity(0).accessibilityHidden(true)
        }
        .environment(\.look, look)
    }

    private func go(_ step: Int) {
        withAnimation(Animation.reduced ? nil : .smooth(duration: 0.35)) {
            page = min(max(page + step, 0), pages.count - 1)
        }
    }

    private func text(_ title: String, _ body: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 26, weight: .semibold))
            Text(body).font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}
