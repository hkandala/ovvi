import HerdrKit
import SwiftUI

/// The welcome's herdr step, only while This Mac has no herdr: Install runs the app's own install (`HerdrInstall`,
/// ui/states), with its progress, and a failure with Retry. Next waits for `found`.
struct HerdrStep: View {
    @Binding var found: Bool
    @Environment(\.look) private var look

    var body: some View {
        let machine = Machine.thisMac
        // The page's title and line say why (WelcomeView); this is the picture's place: herdr's logo and its install.
        VStack(spacing: 20) {
            if found {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 76)).foregroundStyle(look.finished)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                Text("herdr is installed").font(.system(size: 15, weight: .medium))
            } else {
                // herdr's own logo (github.com/herdrdev/herdr, assets/logo.svg; Apache-2.0, Acknowledgements).
                Image("HerdrLogo").resizable().scaledToFit().frame(width: 112, height: 112).foregroundStyle(.primary)
                    .accessibilityLabel("herdr")
                switch HerdrInstall.shared.steps[machine.id] {
                case let .running(line):
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(line.isEmpty ? "Installing herdr…" : line).font(.system(size: 13))
                            .foregroundStyle(.secondary).lineLimit(1).accessibilityIdentifier("welcome.herdr.progress")
                    }
                    .frame(height: 32)
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

    private func install() {
        Task { await HerdrInstall.shared.install(on: .thisMac) }
    }

    static func missing() async -> Bool {
        await (try? Machine.thisMac.exec().herdr()) == nil
    }
}
