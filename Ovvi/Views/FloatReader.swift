import SwiftUI

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
        if reader.terminalID != terminalID {
            FloatFrames.windows.removeObject(forKey: reader.terminalID as NSString)
            reader.terminalID = terminalID
            reader.register()
        }
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

        /// Also when a replaced pane's new one takes the window.
        func register() {
            guard let window else { return }
            // ponytail: one defaults key per terminal ever floated; prune them if that ever matters.
            FloatFrames.windows.setObject(window, forKey: terminalID as NSString)
            window.setFrameAutosaveName("float \(terminalID)")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            pin()
            register()
            FloatFrames.keepKey(window, terminalID)
            let center = NotificationCenter.default, close = NSWindow.willCloseNotification
            observers.append(center.addObserver(forName: close, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // A closed window stays alive for a while: never brought back by FloatFrames.open.
                    if let self, FloatFrames.windows.object(forKey: self.terminalID as NSString) === self.window {
                        FloatFrames.windows.removeObject(forKey: self.terminalID as NSString)
                    }
                    self?.closed()
                    self?.stop()
                }
            })
        }
    }
}
