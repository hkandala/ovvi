import SwiftUI

/// Resume is a button over the row, not in its label: there it would be part of the row's one accessibility element.
struct ArchivedRow: View {
    let icon: String
    let title: String
    let line2: String
    let date: Date
    let id: String
    let resume: () -> Void
    @State private var hovering = false
    @Environment(\.look) private var look

    var body: some View {
        Button(action: resume) {
            HStack(alignment: .top, spacing: 8) {
                ProgramTile(icon: icon)
                lines {
                    Text(title).font(.system(size: 13)).lineLimit(1).foregroundStyle(look.chrome)
                    Spacer(minLength: 0)
                    if hovering {
                        resumeButton.hidden().accessibilityHidden(true)
                    }
                    AgeText(date: date)
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 48)
        }
        .buttonStyle(ChromeStyle(radius: 6))
        .accessibilityIdentifier(id)
        .accessibilityLabel("\(title), \(line2)")
        .overlay {
            if hovering {
                lines(line2: false) {
                    Spacer(minLength: 0)
                    resumeButton
                    AgeText(date: date).hidden().accessibilityHidden(true)
                }
                .padding(.horizontal, 4)
            }
        }
        .onHover { hovering = $0 }
    }

    private var resumeButton: some View {
        IconButton(symbol: "arrow.uturn.backward", help: "Resume", size: 18, action: resume)
            .accessibilityIdentifier(id + ".resume")
    }

    private func lines(line2 shown: Bool = true, @ViewBuilder _ first: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) { first() }.frame(height: 18)
            Text(line2).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).opacity(shown ? 1 : 0)
                .accessibilityHidden(!shown)
        }
    }
}

private struct AgeText: View {
    let date: Date

    var body: some View {
        TimelineView(.everyMinute) { _ in
            Text(Self.age(date)).font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    static func age(_ date: Date) -> String {
        let minutes = max(0, Int(Date.now.timeIntervalSince(date))) / 60
        return switch minutes {
        case ..<60: "\(minutes)m"
        case ..<(60 * 24): "\(minutes / 60)h"
        case ..<(60 * 24 * 7): "\(minutes / 60 / 24)d"
        default: "\(minutes / 60 / 24 / 7)w"
        }
    }
}
