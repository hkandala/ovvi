import AppKit
import SwiftUI

/// SwiftUI places a new floating window at the frame asked for with it (`defaultWindowPlacement`): a frame set once the
/// window shows can lose to SwiftUI's default size, which sometimes comes after it (46 pt short on CI).
@MainActor
enum FloatFrames {
    static let windows = NSMapTable<NSString, NSWindow>.strongToWeakObjects()
    private static var next: NSRect?

    static func open(_ floating: Floating, over main: NSWindow?, frame: NSRect? = nil, agent: Bool = false,
                     with open: OpenWindowAction?)
    {
        let window = windows.object(forKey: floating.terminalID as NSString)
        if agent, let window {
            return window.orderFrontRegardless()
        }
        if window == nil {
            next = frame ?? saved(floating.terminalID) ?? main.map(frame(over:))
        }
        if agent {
            quiet[floating.terminalID] = .some(NSApp.keyWindow)
        }
        open?(id: WindowPages.floatScene, value: floating)
    }

    static var quiet: [String: NSWindow?] = [:]

    static func keepKey(_ window: NSWindow, _ terminalID: String) {
        guard let previous = quiet.removeValue(forKey: terminalID) else { return }
        Task { window.orderFrontRegardless() }
        guard let previous else { return }
        let center = NotificationCenter.default
        let observer = center
            .addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { previous.makeKey() }
            }
        Task {
            if window.isKeyWindow {
                previous.makeKey()
            }
            try? await Task.sleep(for: .seconds(1))
            center.removeObserver(observer)
        }
    }

    /// `WindowPlacement` takes the screen's top-left based points.
    static func placement() -> WindowPlacement {
        defer { next = nil }
        guard let frame = next, let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) })
            ?? NSScreen.main else { return WindowPlacement() }
        return WindowPlacement(CGPoint(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY),
                               size: frame.size)
    }

    static func frame(over main: NSWindow) -> NSRect {
        let width = max(720, main.frame.width * 0.6), height = max(460, main.frame.height * 0.75)
        let frame = NSRect(x: main.frame.midX - width / 2, y: main.frame.midY - height / 2, width: width,
                           height: height)
        return main.constrainFrameRect(frame, to: main.screen)
    }

    /// AppKit's saved frame (`setFrameAutosaveName`): "x y width height …".
    private static func saved(_ terminalID: String) -> NSRect? {
        let parts = UserDefaults.standard.string(forKey: "NSWindow Frame float \(terminalID)")?
            .split(separator: " ").compactMap { Double($0) } ?? []
        return parts.count >= 4 ? NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]) : nil
    }
}

struct FloatReader: NSViewRepresentable {
    let terminalID: String
    let pinned: Bool
    let closed: () -> Void

    func makeNSView(context _: Context) -> Reader {
        let reader = Reader()
        reader.terminalID = terminalID
        return reader
    }

    func updateNSView(_ reader: Reader, context _: Context) {
        reader.closed = closed
        reader.pinned = pinned
    }

    final class Reader: TrafficLights {
        var closed: () -> Void = {}
        var terminalID = ""
        /// Applied again as the view joins its window: SwiftUI's first update comes while it has none.
        var pinned = false {
            didSet { pin() }
        }

        private func pin() {
            window?.level = pinned ? .floating : .normal
            let onTop: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            if pinned {
                window?.collectionBehavior.formUnion(onTop)
            } else {
                window?.collectionBehavior.subtract(onTop)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            pin()
            // ponytail: one defaults key per terminal ever floated; prune them if that ever matters.
            FloatFrames.windows.setObject(window, forKey: terminalID as NSString)
            window.setFrameAutosaveName("float \(terminalID)")
            FloatFrames.keepKey(window, terminalID)
            let center = NotificationCenter.default, close = NSWindow.willCloseNotification
            observers.append(center.addObserver(forName: close, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.closed()
                    self?.stop()
                }
            })
        }
    }
}
