import SwiftUI

extension View {
    /// The app's tooltip, in place of `.help`: drawn by the window's `hoverPanelHost`, with the key as a key cap.
    func tip(_ text: String, key: KeyboardShortcut? = nil) -> some View {
        modifier(TipTrigger(text: text, key: key?.glyphs))
    }
}

struct Tip {
    let owner: UUID
    var trigger: CGRect
    let text: String
    let key: String?
    /// None when it follows another tip: the pointer moved along a row of buttons.
    var fades = true
}

/// 0.5 s on a button shows its tip; within 0.5 s of the last tip, the next shows at once. A click, a scroll or a key
/// hides it, and the next one waits again.
extension HoverPanels {
    func enter(_ tip: Tip) {
        wait?.cancel()
        watch()
        // None while a button is held: a drag, or a menu opening.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        if self.tip != nil || tipEnded.map({ ContinuousClock.now - $0 < .milliseconds(500) }) == true {
            self.tip = tip
            self.tip?.fades = false
            return
        }
        waiting = tip
        wait = Task {
            // Cancelled, the next button's wait is the one that counts.
            guard await (try? Task.sleep(for: .milliseconds(500))) != nil else { return }
            if NSEvent.pressedMouseButtons == 0 {
                self.tip = waiting
            }
            waiting = nil
        }
    }

    func leave(_ owner: UUID) {
        if waiting?.owner == owner {
            wait?.cancel()
            waiting = nil
        }
        if tip?.owner == owner {
            tip = nil
            tipEnded = .now
        }
        if tip == nil, waiting == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    func move(_ owner: UUID, to frame: CGRect) {
        if waiting?.owner == owner {
            waiting?.trigger = frame
        }
        if tip?.owner == owner {
            tip?.trigger = frame
        }
    }

    private func watch() {
        guard monitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        monitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated {
                self?.wait?.cancel()
                self?.waiting = nil
                self?.tip = nil
                self?.tipEnded = nil
            }
            return event
        }
    }
}

private struct TipTrigger: ViewModifier {
    let text: String
    let key: String?
    @Environment(HoverPanels.self) private var panels: HoverPanels?
    @Environment(\.isEnabled) private var enabled
    @State private var id = UUID()
    /// Not observed: a write at every move would redraw the trigger.
    @State private var frame = Frame()
    private final class Frame {
        var rect = CGRect.zero
    }

    func body(content: Content) -> some View {
        content
            .environment(\.isEnabled, enabled)
            .onHover { over in
                guard let panels else { return }
                if over, !text.isEmpty {
                    panels.enter(Tip(owner: id, trigger: frame.rect, text: text, key: key))
                } else {
                    panels.leave(id)
                }
            }
            // SwiftUI sends a disabled view no hover: the button stays disabled, and its tip still shows.
            .environment(\.isEnabled, true)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                frame.rect = rect
                panels?.move(id, to: rect)
            }
            // A view removed under the pointer gets no hover end.
            .onDisappear { panels?.leave(id) }
            // As `.help` did: VoiceOver reads it as help.
            .accessibilityHint(text)
    }
}

/// A solid panel with a fine rim, and the key in one outlined cap.
struct TipView: View {
    let tip: Tip
    @Environment(\.look) private var look

    var body: some View {
        let colors = look.tip, shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 8) {
            Text(tip.text)
            if let key = tip.key {
                Text(key).font(.system(size: 11, weight: .medium)).kerning(0.5).fixedSize()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(colors.cap))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(colors.text)
        .padding(.leading, 12).padding(.trailing, tip.key == nil ? 12 : 7).padding(.vertical, 6)
        .background(colors.fill, in: shape)
        .overlay(shape.strokeBorder(colors.rim))
        .shadow(color: colors.shadow, radius: 9, y: 6)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([tip.text, tip.key].compactMap(\.self).joined(separator: " "))
        .accessibilityAddTraits(.isStaticText)
        .accessibilityIdentifier("tooltip")
    }
}
