import AppKit
import HerdrKit
import SwiftUI

struct PathField: View {
    let control: PluginManifest.Control
    let plugin: Plugin
    let page: Page
    let identifier: String
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        let id = control.id ?? "", value = control.value?.text ?? "", remote = page.store.machine.isRemote
        let header = plugin.header, shown = MachinePath.short(value, remote: remote), still = Animation.reduced
        HStack(spacing: 6) {
            Button { header.send?(["id": id]) } label: {
                Image(symbol: control.symbol ?? "folder").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Choose Folder…")
            .accessibilityLabel("Choose Folder…")
            .accessibilityIdentifier("\(identifier).choose")
            TextField(control.label ?? "", text: $draft)
                .focused($editing)
                .blursWhenHidden($editing)
                // Not by opacity: SwiftUI focuses no view at opacity 0.
                .foregroundStyle(editing ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear))
                .accessibilityIdentifier(identifier)
                .overlay(alignment: .leading) {
                    if !editing {
                        Text(shown).lineLimit(1).truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                            .onTapGesture { editing = true }
                            .accessibilityHidden(true)
                    }
                }
                .onSubmit {
                    let typed = remote ? draft : (draft as NSString).expandingTildeInPath
                    let path = MachinePath.tidy(typed.hasPrefix("/") ? typed : value + "/" + typed)
                    if path == value {
                        editing = false
                    } else {
                        header.send?(["id": id, "value": path, "submit": true])
                    }
                }
                .onExitCommand {
                    draft = value
                    editing = false
                    plugin.web.view.takeKeyboard()
                }
        }
        .fieldCapsule()
        .overlay { Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5).opacity(editing ? 1 : 0) }
        .focusEffectDisabled()
        // Not a gated trigger, which plays once as the switch flips: the shake's drawing reads the switch.
        // swiftlint:disable:next animations
        .keyframeAnimator(initialValue: 0.0, trigger: header.refused[id] ?? 0) { field, shift in
            field.offset(x: still ? 0 : shift)
        } keyframes: { _ in
            KeyframeTrack {
                for shift in [-6.0, 6, -4, 4, 0] {
                    LinearKeyframe(shift, duration: 0.06)
                }
            }
        }
        .onChange(of: header.refused[id]) {
            if Animation.reduced {
                NSSound.beep()
            }
        }
        .onChange(of: value, initial: true) {
            draft = value
            editing = false
        }
        .onChange(of: editing) {
            guard editing else {
                draft = value
                return
            }
            page.tookKeyboard(plugin.terminalID)
            DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSText)?.selectAll(nil) }
        }
    }
}
