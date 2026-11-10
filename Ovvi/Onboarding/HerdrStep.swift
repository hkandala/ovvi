import HerdrKit
import SwiftUI

/// The welcome's herdr step, only while This Mac has no herdr: Install runs the app's own install (`HerdrInstall`,
/// ui/states), with its progress, and a failure with Retry. Next waits for `found`.
struct HerdrStep: View {
    @Binding var found: Bool

    @Environment(\.look) private var look

    var body: some View {
        let machine = Machine.thisMac
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: found ? "checkmark.circle" : "shippingbox")
                    .font(.system(size: 44, weight: .light)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(found ? AnyShapeStyle(look.finished) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
                switch HerdrInstall.shared.steps[machine.id] {
                case let .running(line):
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(line.isEmpty ? "Installing herdr…" : line).font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1).accessibilityIdentifier("welcome.herdr.progress")
                    }
                case let .failed(text):
                    Text(text).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(4)
                        .multilineTextAlignment(.center).textSelection(.enabled)
                        .accessibilityIdentifier("welcome.herdr.failure")
                    Button("Retry", action: install).buttonStyle(.glass).controlSize(.large)
                        .accessibilityIdentifier("welcome.herdr.install")
                case nil where !found:
                    Button("Install herdr", action: install).buttonStyle(.glassProminent).controlSize(.large)
                        .accessibilityIdentifier("welcome.herdr.install")
                case nil:
                    EmptyView()
                }
            }
            .padding(24)
            .frame(width: WelcomePicture.size.width, height: WelcomePicture.size.height)
            .background(look.cardFill, in: shape)
            .overlay(shape.strokeBorder(look.divider.opacity(0.6), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 22, weight: .semibold))
                Text(words).font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6).padding(.top, 16)
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

    private var title: String {
        if found {
            return "herdr is installed"
        }
        if case .failed = HerdrInstall.shared.steps[Machine.thisMac.id] {
            return "herdr did not install"
        }
        return "One more thing: herdr"
    }

    private var words: String {
        found ? "Your sessions have a home on This Mac. Get Started, and open a folder or a session."
            : """
            Ovvi keeps your terminals and agents in herdr sessions, so they go on after Ovvi quits. This Mac \
            doesn't have herdr yet: Install herdr sets it up with herdr's own installer.
            """
    }

    private func install() {
        Task { await HerdrInstall.shared.install(on: .thisMac) }
    }

    static func missing() async -> Bool {
        await (try? Machine.thisMac.exec().herdr()) == nil
    }
}
