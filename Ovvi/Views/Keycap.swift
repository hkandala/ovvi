import SwiftUI

struct Keycap: View {
    let text: String

    var body: some View {
        // One glyph's cap is as wide as the widest (⌘), so a palette row's caps line up.
        Text(text).font(.system(size: 10, weight: .semibold)).fixedSize().frame(minWidth: 10)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .glassEffect(.regular, in: .rect(cornerRadius: 4))
    }
}
