import Carbon.HIToolbox
import HerdrKit
import SwiftUI

struct PanelPlace {
    let trigger: UnitPoint
    let panel: UnitPoint
    let offset: CGSize

    static let under = PanelPlace(trigger: .bottom, panel: .top,
                                  offset: CGSize(width: 0, height: (TitleBar.height - TabBar.height) / 2 + 6))
    static let beside = PanelPlace(trigger: .topTrailing, panel: .topLeading,
                                   offset: CGSize(width: 4 + Sidebar.rowInsets.trailing + gap + 6, height: 0))
}

extension View {
    /// In the window, not a `.popover`: a popover is a window that takes the keyboard when it shows, and a resting
    /// pointer must not take keys from the terminal.
    func hoverPanel(place: PanelPlace, action: String? = nil, light: RowLight? = nil,
                    @ViewBuilder _ panel: @escaping (_ close: @escaping () -> Void) -> some View) -> some View
    {
        modifier(HoverPanel(place: place, action: action, light: light, panel: panel))
    }

    @ViewBuilder
    func onHover(if tracks: Bool, perform action: @escaping (Bool) -> Void) -> some View {
        if tracks {
            onHover(perform: action)
        } else {
            self
        }
    }

    func hoverPanelHost() -> some View {
        modifier(HoverPanelHost())
    }
}

/// Not a preference: one that every tab capsule writes is combined at every update of the window, 100–150 ms of the
/// main thread in a pass of tab switches, swipes and overview opens.
@MainActor @Observable
final class HoverPanels {
    var open: OpenPanel?
}

private struct HoverPanelHost: ViewModifier {
    @State private var panels = HoverPanels()

    func body(content: Content) -> some View {
        content.environment(panels).overlay {
            // Always here, so the panel is the view inserted and scales about its own edge, not the window's.
            GeometryReader { proxy in
                let open = panels.open, origin = proxy.frame(in: .global).origin
                let trigger = open?.trigger.offsetBy(dx: -origin.x, dy: -origin.y) ?? .zero
                PanelLayout(trigger: trigger, place: open?.place ?? .under) {
                    // In only: the panel would lose its place on the way out.
                    if let open {
                        open.content.id(open.owner).transition(.asymmetric(
                            insertion: .opacity.combined(with: Animation.reduced ? .identity
                                : .scale(scale: 0.97, anchor: open.place.panel))
                                .animation(.easeOut(duration: 0.13)),
                            removal: .identity,
                        ))
                    }
                }
            }
        }
    }
}

struct OpenPanel {
    let owner: UUID
    var trigger: CGRect
    let place: PanelPlace
    let content: AnyView
}

private struct PanelLayout: Layout {
    let trigger: CGRect
    let place: PanelPlace

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let panel = subviews.first else { return }
        let size = panel.sizeThatFits(.unspecified)
        let left = trigger.minX + trigger.width * place.trigger.x - size.width * place.panel.x + place.offset.width
        let top = trigger.minY + trigger.height * place.trigger.y - size.height * place.panel.y + place.offset
            .height
        panel.place(at: CGPoint(x: bounds.minX + min(max(left, gap), bounds.width - gap - size.width),
                                y: bounds.minY + min(max(top, gap), bounds.height - gap - size.height)),
                    proposal: ProposedViewSize(size))
    }
}

private struct HoverPanel<Panel: View>: ViewModifier {
    let place: PanelPlace
    let action: String?
    let light: RowLight?
    let panel: (_ close: @escaping () -> Void) -> Panel
    @State private var open = false
    @State private var overTrigger = false
    @State private var overPanel = false
    @State private var panelFrame = CGRect.null
    @State private var pending: Task<Void, Never>?
    @State private var monitor: Any?
    @State private var window: NSWindow?
    @Environment(\.isEnabled) private var enabled
    @Environment(HoverPanels.self) private var panels: HoverPanels?
    @State private var id = UUID()
    /// Not observed: a write at every move (the tab bar's capsules while the row scrolls) redraws every trigger at
    /// every frame.
    @State private var trigger = Trigger()
    private final class Trigger {
        var frame = CGRect.zero
    }

    func body(content: Content) -> some View {
        let over = light?.lit
        content
            .onHover(if: light == nil) { overTrigger = $0
                hovered()
            }
            .onChange(of: over) {
                overTrigger = over ?? false
                hovered()
            }
            // A click is not a rest: no panel until the pointer comes back (onHover fires only on entering).
            .simultaneousGesture(TapGesture().onEnded {
                overTrigger = false
                hovered()
            })
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                trigger.frame = frame
                if open, panels?.open?.owner == id {
                    panels?.open?.trigger = frame
                }
            }
            .accessibilityActions {
                if let action {
                    Button(action) { show(true) }
                }
            }
            .onChange(of: enabled) {
                if !enabled {
                    show(false)
                }
            }
            .onDisappear { show(false) }
    }

    private func hovered() {
        pending?.cancel()
        let over = enabled && (overTrigger || overPanel)
        guard over != open, !over || NSEvent.pressedMouseButtons == 0 else { return }
        pending = Task {
            try? await Task.sleep(for: .milliseconds(over ? 250 : 150))
            if !Task.isCancelled, !over || NSEvent.pressedMouseButtons == 0 {
                show(over || enabled && pointerInPanel)
            }
        }
    }

    /// By its frame: a busy app runs the panel's hover late, after the trigger's grace or a click in it.
    private var pointerInPanel: Bool {
        guard open, let window, let height = window.contentView?.bounds.height else { return false }
        let point = window.mouseLocationOutsideOfEventStream
        return panelFrame.contains(CGPoint(x: point.x, y: height - point.y))
    }

    private func show(_ value: Bool) {
        pending?.cancel()
        open = value
        if value {
            panels?.open = OpenPanel(
                owner: id,
                trigger: trigger.frame,
                place: place,
                content: AnyView(panel { show(false) }
                    .onHover { overPanel = $0
                        hovered()
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { panelFrame = $0 }),
            )
        } else if panels?.open?.owner == id {
            panels?.open = nil
        }
        if value, monitor == nil {
            let under = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
            window = NSApp.window(withWindowNumber: under) ?? NSApp.keyWindow
            let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]
            monitor = NSEvent.addLocalMonitorForEvents(matching: events) { event in
                guard event.type != .keyDown || Int(event.keyCode) == kVK_Escape && event.window === window
                else { return event }
                let escape = event.type == .keyDown
                let swallow = MainActor.assumeIsolated {
                    if escape || !overPanel && !pointerInPanel {
                        show(false)
                    }
                    return escape && !(window?.firstResponder is NSText)
                }
                return swallow ? nil : event
            }
        } else if !value {
            // A panel that goes from under the pointer sends no hover exit.
            overPanel = false
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

/// A blocked agent's row shows its last screen lines: herdr 0.9.5 sends no blocked message.
struct HoverCard: View {
    let tabID: String
    let page: Page
    let close: () -> Void
    @State private var lines: [String: [String]] = [:]

    var body: some View {
        let store = page.store
        if let workspace = store.workspace(of: tabID), let tab = store.tab(tabID) {
            let panes = store.panes(in: tabID)
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    page.select(workspace, tab: tabID)
                    close()
                } label: {
                    FadeText(text: page.titleLabel(tab)).fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .frame(height: 26)
                }
                .buttonStyle(ChromeStyle(radius: 6))
                .accessibilityIdentifier("hovercard.title")
                ForEach(panes.prefix(6)) { pane in row(pane) }
                if panes.count > 6 {
                    Text("+\(panes.count - 6) more").font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                }
            }
            .padding(6)
            .frame(width: 280, alignment: .leading)
            .floatingGlass(in: .rect(cornerRadius: 12))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Panes of \(page.titleText(tab))")
            .accessibilityIdentifier("hovercard")
            .task {
                guard let client = store.client else { return }
                for pane in panes.prefix(6) where pane.state == .needsYou {
                    if let text = try? await client.screen(pane.id) {
                        lines[pane.id] = text.split(whereSeparator: \.isNewline)
                            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(3)
                    }
                }
            }
        }
    }

    private func row(_ pane: HostStore.Pane) -> some View {
        let kind = pane.agent == nil ? page.kindTitle(pane) : nil
        let shown = lines[pane.id] ?? [], name = kind?.name ?? pane.agentName ?? pane.programName ?? "terminal"
        let detail = kind == nil ? pane.folder : kind?.detail
        let state = pane.state?.shown
        return Button {
            page.go(to: pane)
            close()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ProgramGlyph(icon: pane.iconID, letter: pane.letter)
                    Text(name).lineLimit(1).layoutPriority(1)
                    Text(detail ?? "").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.trailing, state == nil ? 0 : 18)
                ForEach(shown.indices, id: \.self) { index in
                    Text(shown[index]).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(minHeight: 26)
        }
        .buttonStyle(ChromeStyle(radius: 6))
        .accessibilityIdentifier("hovercard.\(pane.id)")
        .accessibilityLabel([name, detail].compactMap(\.self).joined(separator: ", "))
        .accessibilityValue(([pane.state?.title].compactMap(\.self) + shown).joined(separator: "\n"))
        // Over the button, so a test sees it.
        .overlay(alignment: .topTrailing) {
            if let state {
                StateIcon(state: state).stateElement(state, "hovercard.\(pane.id).state")
                    .frame(height: 26).padding(.trailing, 6).allowsHitTesting(false)
            }
        }
    }
}
