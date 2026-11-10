import HerdrKit
import SwiftUI

/// The welcome's herdr step, only while This Mac has no herdr: Install runs the app's own install (`HerdrInstall`,
/// ui/states), with its progress, and a failure with Retry. Next waits for `found`.
struct HerdrStep: View {
    @Binding var found: Bool
    @Environment(\.look) private var look

    var body: some View {
        let machine = Machine.thisMac
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let edge = look.edge(keyboard: false)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: found ? "checkmark.circle" : "shippingbox").font(.system(size: 30, weight: .light))
                    .foregroundStyle(found ? look.finished : .secondary).symbolRenderingMode(.hierarchical)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(found ? "herdr is installed" : "Ovvi needs herdr").font(.system(size: 15, weight: .semibold))
                    Text("herdr keeps your terminals and agents running in sessions, so they go on after Ovvi quits.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Group {
                switch HerdrInstall.shared.steps[machine.id] {
                case let .running(line):
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(line.isEmpty ? "Installing herdr…" : line).font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).accessibilityIdentifier("welcome.herdr.progress")
                    }
                case let .failed(text):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("herdr did not install").font(.system(size: 13, weight: .medium))
                        Text(text).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(4)
                            .textSelection(.enabled).accessibilityIdentifier("welcome.herdr.failure")
                        Button("Retry", action: install).buttonStyle(.glass)
                            .accessibilityIdentifier("welcome.herdr.install")
                    }
                case nil where !found:
                    HStack(spacing: 12) {
                        Button("Install", action: install).buttonStyle(.glassProminent).controlSize(.large)
                            .accessibilityIdentifier("welcome.herdr.install")
                        Text(HerdrInstall.command).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                case nil:
                    EmptyView()
                }
            }
            .padding(.leading, 50)
        }
        .padding(22)
        .frame(width: 460, alignment: .leading)
        .background(look.paletteField, in: shape)
        .overlay(shape.strokeBorder(edge.color, lineWidth: edge.width))
        .shadow(color: look.floatShadow, radius: 14, y: 7)
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
