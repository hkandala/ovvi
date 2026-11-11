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
