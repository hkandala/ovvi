import SwiftUI

extension VerticalAlignment {
    nonisolated enum ReplyBox: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    /// A custom guide, as a stack passes on only those: `center` is the stack's own.
    nonisolated static let replyBox = VerticalAlignment(ReplyBox.self)
}

/// The empty chat's: the reply box's middle at one line in the card's, its header above it, and the stack's top no
/// higher than the card's (a short card keeps the header). Otherwise the stack at its own height.
struct BoxInMiddle: Layout {
    let fills: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        return fills ? CGSize(width: size.width, height: max(size.height, proposal.height ?? 0)) : size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard let stack = subviews.first else { return }
        let offer = ProposedViewSize(width: bounds.width, height: nil)
        let height = stack.sizeThatFits(offer).height
        let top = fills ? max(bounds.minY, bounds.midY - stack.dimensions(in: offer)[.replyBox]) : bounds.maxY - height
        // The offer it was measured with: offered its height, the stack shares it out its own way, and the greeting
        // shrinks as the reply box grows.
        stack.place(at: CGPoint(x: bounds.minX, y: top), proposal: offer)
    }
}
