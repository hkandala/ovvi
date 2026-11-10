import SwiftUI

/// A window before its first page or the new-window view: already its own background and title row, so it never shows
/// a plain window first; at launch (every window macOS restores, or the first new one) Ovvi's icon shows in the middle
/// meanwhile, until a window of the launch has its content.
struct WindowStart: View {
    let pages: WindowPages
    @State private var icon = !WindowStart.started
    /// A window of this launch shows its content: later windows (⌘N, a Dock reopen) show no icon.
    static var started = false
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(pages: WindowPages) {
        self.pages = pages
    }

    var body: some View {
        let look = Look(style: settings.style, dark: colorScheme == .dark, contrast: colorSchemeContrast == .increased)
        Color.clear
            .overlay {
                if icon {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                        .padding(.bottom, TitleBar.height).accessibilityHidden(true)
                }
            }
            .windowChrome(look)
            .background(WindowReader(pages: pages, fullScreen: .constant(false), lightsOff: .constant(0)))
    }
}
