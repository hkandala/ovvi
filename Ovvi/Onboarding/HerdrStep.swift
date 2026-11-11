import HerdrKit
import SwiftUI

/// The welcome's herdr step, only while This Mac has no herdr: Install runs the app's own install (`HerdrInstall`,
/// ui/states), with its progress, and a failure with Retry. Next waits for `found`.
struct HerdrStep: View {
    @Binding var found: Bool
    @Environment(\.look) private var look
    @State private var started = false

    var body: some View {
        let machine = Machine.thisMac
        // The page's title and line say why (WelcomeView); this is the picture's place: herdr's logo and its install.
        VStack(spacing: 20) {
            if found {
                // All set: a green check on the logo's tile.
                tile(Image(systemName: "checkmark").font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(look.finished))
                    .accessibilityHidden(true).transition(.scale(scale: 0.9).combined(with: .opacity))
                Text("herdr is installed").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
            } else {
                // herdr's own logo as it is (github.com/herdrdev/herdr, assets/logo.png; Apache-2.0, Acknowledgements),
                // on a tile with an app icon's corners.
                tile(Image("HerdrLogo").resizable().scaledToFill()).accessibilityLabel("herdr")
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
                case nil where started:
                    // The install has ended; the lookup finds herdr within a second.
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking herdr…").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .frame(height: 32)
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

    private func tile(_ content: some View) -> some View {
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)
        return content.frame(width: 72, height: 72).background(look.cardSolid(), in: shape).clipShape(shape)
            .overlay(shape.strokeBorder(look.divider))
    }

    private func install() {
        started = true
        Task { await HerdrInstall.shared.install(on: .thisMac) }
    }

    static func missing() async -> Bool {
        await (try? Machine.thisMac.exec().herdr()) == nil
    }
}
