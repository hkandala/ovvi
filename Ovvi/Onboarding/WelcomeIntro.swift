import SwiftUI

/// The welcome's intro (ui/welcome): the logo's three panes come in back to front with the name under them, then they
/// slide apart and resize into the window of the first page's picture, its sidebar and two panes, as the name fades
/// out; the picture then fades in over them.
struct WelcomeIntro: View {
    enum Step {
        case hidden, mark, panes
    }

    let step: Step
    /// Where the logo sits: its centre, in the panel's points.
    let center: CGPoint
    /// Where the logo's panes go, back to front, in the panel's points.
    let panes: [CGRect]
    @Environment(\.look) private var look

    /// The logo's panes in the artwork's pixels (resources/branding/ovvi-flat-stack-original.png, 783 x 668 across
    /// the three), its corner radius and the gutter that sets each pane off the one behind it.
    private static let artwork = [CGRect(x: 0, y: 0, width: 560, height: 392),
                                  CGRect(x: 114, y: 135, width: 561, height: 394),
                                  CGRect(x: 222, y: 269, width: 561, height: 399)]
    private static let size = CGSize(width: 783, height: 668), radius: CGFloat = 60, gutter: CGFloat = 15
    /// Points per artwork pixel: the logo is 220 pt wide.
    private static let scale: CGFloat = 220 / 783

    var body: some View {
        let inPanes = step == .panes
        ZStack {
            ForEach(0 ..< 3, id: \.self) { index in
                let frame = inPanes ? panes[index] : logo(index)
                let shape = RoundedRectangle(cornerRadius: inPanes ? 10 * WelcomeView.pictureScale
                    : Self.radius * Self.scale,
                    style: .continuous)
                Group {
                    // The gutter: the pane in front cuts the ones behind it.
                    if index > 0 {
                        shape.inset(by: inPanes ? 0 : -Self.gutter * Self.scale).fill()
                            .frame(width: frame.width, height: frame.height).blendMode(.destinationOut)
                    }
                    ZStack {
                        // In light the pearl pane sits on light glass: a hairline keeps its edge.
                        LinearGradient(colors: [Look.mark[index].0, Look.mark[index].1], startPoint: .top,
                                       endPoint: .bottom)
                            .overlay(shape.strokeBorder(look.dark ? .clear : look.divider))
                            .opacity(inPanes ? 0 : 1)
                        // A pane's outline, so the panes still read as cards while the picture comes in.
                        shape.fill(look.track).overlay(shape.strokeBorder(look.divider)).opacity(inPanes ? 1 : 0)
                    }
                    .clipShape(shape).frame(width: frame.width, height: frame.height)
                }
                .position(x: frame.midX, y: frame.midY)
                .opacity(step == .hidden ? 0 : 1)
                .offset(y: step == .hidden && !Animation.reduced ? 10 : 0)
                .animation(animation(index), value: step)
            }
        }
        .compositingGroup()
        .overlay {
            Text("Ovvi").font(.system(size: 38, weight: .semibold)).tracking(step == .mark ? 0.4 : 2)
                .foregroundStyle(.primary)
                .position(x: center.x, y: center.y + Self.size.height * Self.scale / 2 + 52)
                .opacity(step == .mark ? 1 : 0).blur(radius: step == .mark ? 0 : 4)
                .animation(.smooth(duration: step == .panes ? 0.35 : 0.7).delay(step == .mark ? 0.25 : 0),
                           value: step)
        }
        .allowsHitTesting(false)
        // The tests wait for it to go.
        .accessibilityElement().accessibilityLabel("Ovvi").accessibilityIdentifier("welcome.intro")
    }

    /// Pane `index` of the logo, in the panel's points.
    private func logo(_ index: Int) -> CGRect {
        let art = Self.artwork[index], scale = Self.scale
        let origin = CGPoint(x: center.x - Self.size.width * scale / 2, y: center.y - Self.size.height * scale / 2)
        return CGRect(x: origin.x + art.minX * scale, y: origin.y + art.minY * scale, width: art.width * scale,
                      height: art.height * scale)
    }

    /// Back to front as they come in; in the same order, a beat apart, as they spread into panes.
    private func animation(_ index: Int) -> Animation {
        switch step {
        case .hidden: .default
        case .mark: .spring(duration: 0.6, bounce: 0.18).delay(Double(index) * 0.09)
        case .panes: .spring(duration: 0.75, bounce: 0.1).delay(Double(index) * 0.05)
        }
    }
}
