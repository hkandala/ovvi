import SwiftUI

/// The important keys; Settings ▸ Keyboard Shortcuts has them all.
struct Shortcuts: View {
    @FocusState private var focused: Bool

    var body: some View {
        let rows = Self.rows(), first = ["Panes", "Tabs"]
        let panel = VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 48) {
                column(first, rows)
                column(Hotkeys.groups.filter { !first.contains($0) }, rows)
            }
            Button("Customize…") { SettingsRoute.shared.open(.keys) }
                .buttonStyle(.glass).accessibilityIdentifier("shortcuts.customize")
        }
        .padding(.horizontal, 28).padding(.vertical, 24)
        // ponytail: a window under about 870 pt wide clips its sides; a scroll view on both axes fills the whole
        // window.
        ViewThatFits(in: .vertical) {
            panel
            ScrollView { panel }.scrollIndicators(.never)
        }
        .floatingGlass(in: .panel)
        .padding(.vertical, 16)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shortcuts")
    }

    private func column(_ groups: [String], _ rows: [Row]) -> some View {
        let groups = groups.filter { group in rows.contains { $0.group == group } }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.self) { group in
                Text(group).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.top, group == groups.first ? 0 : 18).padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("shortcuts.section.\(group)")
                ForEach(rows.filter { $0.group == group }, id: \.title) { row in
                    HStack(spacing: 4) {
                        Text(row.title)
                        Spacer(minLength: 24)
                        ForEach(Array(row.keys.enumerated()), id: \.offset) { index, caps in
                            if index > 0 {
                                Text("or").foregroundStyle(.secondary).padding(.horizontal, 4)
                            }
                            ForEach(caps, id: \.self, content: Keycap.init)
                        }
                    }
                    .font(.system(size: 13))
                    .frame(height: 30)
                    .readableText(row.keys.map { $0.joined() }.joined(separator: " or "))
                    .accessibilityLabel(row.title)
                    .accessibilityIdentifier("shortcuts.\(row.title)")
                }
            }
        }
        .frame(width: 380)
    }

    private struct Row {
        let group: String
        let title: String
        let keys: [[String]]
    }

    /// A family shows as one row while each of its actions keeps its default keys.
    @MainActor private static func rows() -> [Row] {
        let hotkeys = Hotkeys.shared
        var rows: [Row] = []
        for hotkey in Hotkeys.app where hotkey.top {
            let keys = hotkeys.keys(hotkey)
            guard !keys.isEmpty else { continue }
            if let family = hotkey.family, Hotkeys.app.allSatisfy({ $0.family?.title != family.title
                    || !hotkeys.changed($0) })
            {
                if !rows.contains(where: { $0.title == family.title }), let key = keys.first {
                    rows.append(Row(group: hotkey.group, title: family.title,
                                    keys: [key.caps.dropLast() + [family.keys]]))
                }
                continue
            }
            rows.append(Row(group: hotkey.group, title: hotkey.title.replacing("…", with: ""), keys: keys.map(\.caps)))
        }
        return rows
    }
}
