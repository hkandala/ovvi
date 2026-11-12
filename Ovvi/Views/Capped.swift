import SwiftUI

/// Offers its view at most `width` and takes the view's own size: a `frame(maxWidth:)` takes the whole offer. It places
/// the view with the offer it measured with: its own height would stretch a flexible view.
struct Capped: Layout {
    let width: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(offer(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: offer(proposal))
    }

    private func offer(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? width, width), height: proposal.height)
    }
}
