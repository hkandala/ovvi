import HerdrKit
import SwiftUI

/// The welcome's herdr step, only while This Mac has no herdr: Install runs the app's own install (`HerdrInstall`,
/// ui/states), with its progress, and a failure with Retry. Next waits for `found`.
struct HerdrStep: View {
    @Binding var found: Bool
    @Environment(\.look) private var look

    var body: some View {
        let machine = Machine.thisMac
        let step = HerdrInstall.shared.steps[machine.id]
        // The page's title and sentence say what it is (WelcomeView); this is the picture's place.
        VStack(spacing: 18) {
            if found {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(look.finished)
                    .symbolRenderingMode(.hierarchical).transition(.scale(scale: 0.8).combined(with: .opacity))
                Text("herdr is installed and running").font(.system(size: 15, weight: .medium))
            } else {
                HStack(alignment: .top, spacing: 36) {
                    point("play.circle", "Runs in the background")
                    point("macwindow", "Close the window,\nnothing stops")
                    point("antenna.radiowaves.left.and.right", "Reconnect\nfrom anywhere")
                }
                .padding(.bottom, 8)
                switch step {
                case let .running(line):
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(line.isEmpty ? "Installing herdr…" : line).font(.system(size: 12))
                            .foregroundStyle(.secondary).lineLimit(1).accessibilityIdentifier("welcome.herdr.progress")
                    }
                    .frame(height: 30)
                case let .failed(text):
                    Text("herdr did not install").font(.system(size: 13, weight: .medium))
                    Text(text).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(4)
                        .textSelection(.enabled).accessibilityIdentifier("welcome.herdr.failure")
                    Button("Retry", action: install).buttonStyle(.glass).controlSize(.large)
                        .accessibilityIdentifier("welcome.herdr.install")
                case nil:
                    Button("Install herdr", action: install).buttonStyle(.glassProminent).controlSize(.large)
                        .accessibilityIdentifier("welcome.herdr.install")
                    Text(HerdrInstall.command).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        }
        .animation(Animation.reduced ? nil : .spring(duration: 0.5, bounce: 0.2), value: found)
        // Found however it came: this install, the window's own, one outside Ovvi, or a login shell slower than the
        // lookup's 3 s at launch. A missing herdr is asked about at most every 30 s (`Exec.herdr`).
        .task {
            while !found, !Task.isCancelled {
                found = await (try? Machine.thisMac.exec().herdr()) != nil
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
                .frame(height: 26)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(width: 140)
    }

    private func install() {
        Task { await HerdrInstall.shared.install(on: .thisMac) }
    }

    static func missing() async -> Bool {
        await (try? Machine.thisMac.exec().herdr()) == nil
    }
}
