import SwiftUI

/// A window before its first page or the new-window view: already its own background and title row, so it never shows
/// a plain window first; the launch's first window shows Ovvi's icon in the middle meanwhile (a restore reads herdr).
struct WindowStart: View {
    let pages: WindowPages
    @State private var icon = false
    private static var shown = false
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
            .onAppear {
                icon = !Self.shown
                Self.shown = true
            }
    }
}
