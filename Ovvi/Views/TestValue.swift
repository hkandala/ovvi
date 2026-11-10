import SwiftUI

extension View {
    /// On a one-point text leaf: SwiftUI exposes no value on a container or a plain element. One point, so
    /// accessibility hit tests still find the cards and buttons; last for VoiceOver.
    func testValue(_ id: String, _ label: String, _ value: String, shown: Bool = true) -> some View {
        background(alignment: .topLeading) {
            if shown {
                Color.clear.frame(width: 1, height: 1).readableText(value)
                    .accessibilityLabel(label).accessibilityIdentifier(id).accessibilitySortPriority(-1)
            }
        }
    }
}
