import HerdrKit
import SwiftUI

struct IconPicker: View {
    @Binding var icon: String
    @State private var open = false
    @State private var filter = ""

    var body: some View {
        Button { open = true } label: {
            Image(systemName: icon).frame(width: 36, height: 20)
        }
        .buttonStyle(.glass)
        .help("Icon")
        .accessibilityLabel("Icon")
        .accessibilityValue(icon)
        .accessibilityIdentifier("host.icon")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            let shown = Self.icons.filter { $0.replacing(".", with: " ").matches(filter.replacing(".", with: " ")) }
            VStack(spacing: 8) {
                FilterField(prompt: "Search", text: $filter, identifier: "host.icon.search",
                            symbol: "magnifyingglass", autofocus: true)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 2), count: 10), spacing: 2) {
                        ForEach(shown, id: \.self) { symbol in
                            Button {
                                icon = symbol
                                open = false
                            } label: {
                                Image(systemName: symbol).font(.system(size: 14)).frame(width: 30, height: 30)
                            }
                            .buttonStyle(ChromeStyle(selected: symbol == icon, radius: 7))
                            .help(symbol)
                            .accessibilityLabel(symbol)
                            .accessibilityIdentifier("host.icon.\(symbol)")
                        }
                    }
                }
                .frame(height: 200)
            }
            .padding(10)
            .frame(width: 340)
        }
    }

    static let icons = [
        "laptopcomputer", "desktopcomputer", "macmini", "macstudio", "macpro.gen3", "display", "server.rack",
        "externaldrive", "internaldrive", "cpu", "memorychip", "opticaldiscdrive", "terminal", "apple.terminal",
        "keyboard", "printer", "tv", "appletv", "iphone", "ipad", "applewatch", "visionpro", "gamecontroller",
        "headphones", "hifispeaker", "homepod", "cloud", "icloud", "network", "globe",
        "antenna.radiowaves.left.and.right", "wifi", "dot.radiowaves.left.and.right",
        "point.3.connected.trianglepath.dotted", "cable.connector", "bolt.horizontal", "lock", "shield", "key",
        "house", "building", "building.2", "building.columns", "briefcase", "graduationcap", "books.vertical",
        "book", "flask", "testtube.2", "atom", "brain", "cube", "shippingbox", "archivebox", "tray.full", "folder",
        "doc.text", "chart.bar", "gauge.with.dots.needle.67percent", "hammer", "wrench.and.screwdriver",
        "gearshape", "gearshape.2", "paintbrush", "paintpalette", "pencil", "camera", "film", "music.note", "mic",
        "sparkles", "star", "heart", "flag", "bell", "tag", "bookmark", "leaf", "tree", "mountain.2", "sun.max",
        "moon", "snowflake", "flame", "drop", "bolt", "tortoise", "hare", "ant", "ladybug", "bird", "fish",
        "pawprint", "cat", "dog", "car", "bus", "tram", "airplane", "ferry", "bicycle", "sailboat",
        "globe.americas", "globe.europe.africa", "globe.asia.australia", "map", "location", "mappin.and.ellipse",
        "circle", "square", "triangle", "diamond", "hexagon", "seal", "crown", "trophy", "gift",
        "cup.and.saucer", "fork.knife", "cart", "bag", "creditcard", "banknote", "dollarsign.circle", "person",
        "person.2", "figure.walk", "eye", "hand.raised", "lightbulb", "puzzlepiece", "function",
        "chevron.left.forwardslash.chevron.right", "curlybraces", "number", "textformat",
    ]
}

struct AskDialog: View {
    let question: WindowPages.Question
    let machine: Machine
    @State private var answer = ""
    @FocusState private var focused: Bool

    var body: some View {
        let hostKey = question.text.contains("(yes/no")
        VStack(alignment: .leading, spacing: 12) {
            Label(machine.name, systemImage: machine.icon).font(.system(size: 13, weight: .semibold))
            Text(hostKey ? Self.facts(question.text) : question.text
                .trimmingCharacters(in: .whitespacesAndNewlines))
                .font(hostKey ? .system(size: 12).monospaced() : .system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ask.text")
            if !hostKey {
                HStack(spacing: 6) {
                    Image(systemName: "key").foregroundStyle(.secondary).accessibilityHidden(true)
                    SecureField("", text: $answer)
                        .accessibilityLabel("Answer")
                        .focused($focused)
                        .focusSoon($focused)
                        .onSubmit { question.answer(answer) }
                        .accessibilityIdentifier("ask.answer")
                }
                .fieldCapsule().background(.background.opacity(0.6), in: .capsule)
                .overlay(Capsule().strokeBorder(.primary.opacity(0.2)))
            }
            HStack {
                Spacer()
                Button("Cancel") { question.answer(nil) }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                Button(hostKey ? "Connect" : "OK") { question.answer(hostKey ? "yes" : answer) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("ask.ok")
            }
        }
        .onAppear { AccessibilityNotification.Announcement(question.text).post() }
    }

    static func facts(_ text: String) -> String {
        text.split(separator: "\n").filter { !$0.contains("(yes/no") }.joined(separator: "\n")
            .replacing(#/fingerprint is:? /#, with: "fingerprint is:\n")
    }
}

extension View {
    func dialog() -> some View {
        Color.clear.contentShape(.rect).onTapGesture {}
            .overlay {
                padding(20).frame(width: 440).floatingGlass(in: .panel)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
            }
    }
}
