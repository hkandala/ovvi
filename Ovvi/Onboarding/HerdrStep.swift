import HerdrKit
import SwiftUI

/// The welcome's herdr step, only while This Mac has no herdr: Install runs the app's own install (`HerdrInstall`,
/// ui/states), with its progress, and a failure with Retry. Next waits for `found`.
struct HerdrStep: View {
    @Binding var found: Bool

    var body: some View {
        let machine = Machine.thisMac
        // The page's title and sentence say what it is (WelcomeView); this is the picture's place.
        VStack(spacing: 14) {
            Image(systemName: found ? "checkmark.circle" : "shippingbox").font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary).symbolRenderingMode(.hierarchical).contentTransition(.symbolEffect)
            if found {
                Text("herdr is installed").font(.system(size: 15, weight: .medium))
            }
            switch HerdrInstall.shared.steps[machine.id] {
            case let .running(line):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(line.isEmpty ? "Installing herdr…" : line).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).accessibilityIdentifier("welcome.herdr.progress")
                }
            case let .failed(text):
                Text("herdr did not install").font(.system(size: 13, weight: .medium))
                Text(text).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(4)
                    .textSelection(.enabled).accessibilityIdentifier("welcome.herdr.failure")
                Button("Retry", action: install).buttonStyle(.glass).accessibilityIdentifier("welcome.herdr.install")
            case nil where !found:
                Button("Install", action: install).buttonStyle(.glass).accessibilityIdentifier("welcome.herdr.install")
                Text(HerdrInstall.command).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            case nil:
                EmptyView()
            }
        }
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
