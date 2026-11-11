import SwiftUI

struct WindowStart: View {
    let pages: WindowPages
    @State private var icon = !WindowStart.started
    static var started = false
    private var settings = AppSettings()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

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
