import AppKit
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
