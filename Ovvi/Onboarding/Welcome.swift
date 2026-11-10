import AppKit
import SwiftUI

/// The welcome panel (ui/welcome): a floating panel of its own, no title bar, over Ovvi's windows. It opens by itself
/// on the first launch until it is finished or skipped, and again only from Settings ▸ General.
@MainActor
enum Welcome {
    /// Set when the panel closes (Get Started, Skip or Esc). `-welcomeDone NO` shows it again (the tests).
    static let doneKey = "welcomeDone"
    /// The panel's size, in points, as its pages are drawn.
    static let size = CGSize(width: 960, height: 640)
    private static var panel: NSPanel?

    /// The first launch shows only the panel: the first window opens when it closes.
    static let firstLaunch = !UserDefaults.standard.bool(forKey: doneKey)

    static func showOnFirstLaunch() {
        guard firstLaunch else { return }
        // `-welcomeAfter <seconds>`: a test's film starts recording first.
        Task {
            try? await Task.sleep(for: .seconds(UserDefaults.standard.double(forKey: "welcomeAfter")))
            show()
        }
    }

    private static var opening = false

    /// Learns first whether This Mac has herdr, so the pages never change while the panel shows.
    static func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        guard !opening else { return }
        opening = true
        Task {
            let herdrMissing = await HerdrStep.missing()
            opening = false
            open(herdrMissing: herdrMissing)
        }
    }

    private static func open(herdrMissing: Bool) {
        let panel = Panel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        panel.title = "Welcome to Ovvi" // for VoiceOver and the window list, never drawn
        panel.identifier = NSUserInterfaceItemIdentifier("welcome")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        // Over a main window in full screen too, on the Space in view.
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        // Drawn at its full size and scaled down as a whole on a small screen: at most 80% of the screen; in its
        // middle (scripts/record-window.swift films that rect).
        let visible = NSScreen.main?.visibleFrame ?? CGRect(origin: .zero, size: size)
        let scale = min(1, 0.8 * visible.width / size.width, 0.8 * visible.height / size.height)
        let host = NSHostingView(rootView: WelcomeView(herdrMissing: herdrMissing) { close() }
            .frame(width: size.width, height: size.height).scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale))
        panel.contentView = host
        let fitted = host.fittingSize
        panel.setFrame(
            CGRect(x: (visible.midX - fitted.width / 2).rounded(), y: (visible.midY - fitted.height / 2).rounded(),
                   width: fitted.width, height: fitted.height),
            display: false,
        )
        panel.makeKeyAndOrderFront(nil)
        // The shadow follows the drawn corners, once they are drawn.
        DispatchQueue.main.async { panel.invalidateShadow() }
        self.panel = panel
    }

    static func close() {
        UserDefaults.standard.set(true, forKey: doneKey)
        panel?.orderOut(nil)
        panel = nil
        if !NSApp.windows.contains(where: { $0.canBecomeMain && $0.isVisible }) {
            WindowPages.openWindow?(id: WindowPages.mainScene)
        }
    }

    /// A borderless panel becomes key only when it says so: its buttons' keys (→ ← Return Esc) need it.
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool {
            true
        }

        /// The menu bar's keys would act on the main window behind: none while the panel is key, but Quit, Hide,
        /// Settings and Copy (the herdr step's text). The panel's own keys go first.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            super.performKeyEquivalent(with: event) || event.modifierFlags.contains(.command)
                && !["q", "h", ",", "c"].contains(event.charactersIgnoringModifiers ?? "")
        }
    }
}

/// The panel's background: the window's own glass (Classic: opaque), its corners and a hairline rim.
struct WelcomeBackground: View {
    static let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    @Environment(\.look) private var look

    var body: some View {
        WindowBackground(look: look).clipShape(Self.shape)
            .overlay(Self.shape.strokeBorder(look.rim.all, lineWidth: 1))
    }
}
