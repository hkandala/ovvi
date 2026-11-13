import AppKit
import SwiftUI

/// A window macOS restores in full screen keeps AppKit's empty title bar over the title row (the toolbar's on-hover
/// full screen look holds only when the user enters), so it leaves full screen again.
struct WindowReader: NSViewRepresentable {
    let pages: WindowPages
    @Binding var fullScreen: Bool
    @Binding var lightsOff: Int
    static let recordLights = UserDefaults.standard.bool(forKey: "recordLights")
    /// The last main window's frame as it closed, out of full screen: where a new window opens when none shows.
    static var closedFrame: NSRect?

    func makeNSView(context _: Context) -> Reader {
        let reader = Reader()
        reader.pages = pages
        return reader
    }

    func updateNSView(_ reader: Reader, context _: Context) {
        reader.changed = { fullScreen = $0 }
        reader.lightsOff = { lightsOff += 1 }
    }

    final class Reader: TrafficLights {
        var changed: (Bool) -> Void = { _ in }
        var lightsOff: () -> Void = {}
        weak var pages: WindowPages?
        private var lightsObserver: CFRunLoopObserver?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            pages?.window = window
            let center = NotificationCenter.default
            let close = NSWindow.willCloseNotification
            observers.append(center.addObserver(forName: close, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let window = self?.window, !window.styleMask.contains(.fullScreen) {
                        WindowReader.closedFrame = window.frame
                    }
                    self?.pages?.closed()
                    // The view may go away without leaving its window first.
                    self?.stop()
                }
            })
            // The did ones too: a reader that comes during the change sees no will.
            let notifications = [NSWindow.willEnterFullScreenNotification: true,
                                 NSWindow.willExitFullScreenNotification: false,
                                 NSWindow.didEnterFullScreenNotification: true,
                                 NSWindow.didExitFullScreenNotification: false]
            for (name, value) in notifications {
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.changed(value) }
                })
            }
            if WindowReader.recordLights {
                recordLights()
            }
            // After SwiftUI's update, which may not change state.
            let full = window.styleMask.contains(.fullScreen)
            let restored = AppDelegate.restoredFullScreen.remove(ObjectIdentifier(window)) != nil
            DispatchQueue.main.async { [weak self] in
                self?.changed(full)
                if restored {
                    window.toggleFullScreen(nil)
                }
            }
        }

        private func recordLights() {
            lightsObserver = afterCommit { [weak self] _ in
                if let self, !self.moved().isEmpty {
                    lightsOff()
                }
            }
        }

        override func stop() {
            super.stop()
            lightsObserver.map(CFRunLoopObserverInvalidate)
            lightsObserver = nil
        }
    }
}

extension View {
    /// No toolbar: an empty one's accessibility frame covers the title row on a notched Mac, so a hit test at a tab
    /// capsule finds the toolbar (VoiceOver, XCUITest).
    func windowChrome(_ look: Look) -> some View {
        ignoresSafeArea(edges: .top)
            .containerBackground(for: .window) { WindowBackground(look: look) }
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .windowToolbarFullScreenVisibility(.onHover)
    }
}

/// Rex's traffic lights: 23, 46 and 69 pt from the left, centered on the title row. Public AppKit: plain frame
/// changes of the standard buttons.
class TrafficLights: NSView {
    var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard let window else { return }
        // AppKit lays the buttons out again on title changes (each tab or workspace switch), resizes, key
        // changes and full screen. They go back in this view's layout, after AppKit's tiling and ahead of the
        // draw: a move from the frame notification is dropped for the button AppKit is moving
        // (`setFrameOrigin:ignoreRentry:`), and one on the next turn comes after a draw.
        let place: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.needsLayout = true }
        }
        let center = NotificationCenter.default
        for button in buttons(of: window) {
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: button,
                                                queue: .main, using: place))
        }
        // Leaving full screen, the window still says full screen until it is out.
        observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window,
                                            queue: .main, using: place))
        placeButtons()
    }

    override func layout() {
        super.layout()
        placeButtons()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func buttons(of window: NSWindow) -> [NSButton] {
        [.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
    }

    private func placeButtons() {
        for (button, origin) in moved() {
            button.setFrameOrigin(origin)
        }
    }

    func moved() -> [(button: NSButton, origin: NSPoint)] {
        guard let window, !window.styleMask.contains(.fullScreen) else { return [] }
        return buttons(of: window).enumerated().compactMap { index, button in
            guard let superview = button.superview else { return nil }
            let size = button.frame.size, center = TitleBar.height / 2
            let frame = NSRect(x: center + CGFloat(index) * 23 - size.width / 2,
                               y: window.frame.height - center - size.height / 2, width: size.width,
                               height: size.height)
            let origin = superview.convert(frame, from: nil).origin
            // Only a real move: setting the frame posts the notification that leads here.
            let off = abs(button.frame.minX - origin.x) > 0.1 || abs(button.frame.minY - origin.y) > 0.1
            return off ? (button, origin) : nil
        }
    }
}
