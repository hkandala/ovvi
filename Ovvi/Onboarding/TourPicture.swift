import SwiftUI

/// The welcome's picture: a 2x shot of the window (light and dark in one image set), framed on the page's part of it,
/// and that page's callouts. The camera is the focus rect, animated: the shot pans and zooms to it, and each line's
/// end follows it.
struct TourPicture: View, Animatable {
    /// The part of the shot in view, in the shot's points; the picture fits it, centred.
    var focus: CGRect
    let shot: String
    let callouts: [Callout]
    /// Draws the callouts; set once the camera has moved (they draw one by one, or all at once with Reduce Motion).
    let drawn: Bool
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(focus.midX, focus.midY), .init(focus.width, focus.height)) }
        set {
            focus = CGRect(x: newValue.first.first - newValue.second.first / 2,
                           y: newValue.first.second - newValue.second.second / 2,
                           width: newValue.second.first, height: newValue.second.second)
        }
    }

    var body: some View {
        let size = Tour.picture, scale = min(size.width / focus.width, size.height / focus.height)
        let place = { (point: CGPoint) in
            CGPoint(x: (point.x - focus.midX) * scale + size.width / 2,
                    y: (point.y - focus.midY) * scale + size.height / 2)
        }
        let origin = place(.zero)
        ZStack(alignment: .topLeading) {
            ZStack {
                ForEach([shot], id: \.self) { shot in
                    Image(shot).resizable().interpolation(.high).transition(.opacity)
                }
            }
            .frame(width: Tour.shot.width, height: Tour.shot.height)
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: origin.x, y: origin.y)
            if drawn {
                ForEach(Array(callouts.enumerated()), id: \.offset) { index, callout in
                    CalloutView(callout: callout, from: place(callout.point),
                                delay: reduceMotion ? 0 : Double(index) * 0.3, reduceMotion: reduceMotion)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        // The set the asset catalog shows follows the panel's appearance (the tests read which).
        .accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityIdentifier("welcome.picture")
        .accessibilityValue("\(shot) \(colorScheme == .dark ? "dark" : "light")")
    }
}

/// One keynote callout: a dot on the thing it names, a thin leader line drawn on from it, then the label.
private struct CalloutView: View {
    let callout: Callout
    let from: CGPoint
    let delay: Double
    let reduceMotion: Bool
    @State private var dot = false
    @State private var line: CGFloat = 0
    @State private var label = false
    @Environment(\.look) private var look

    var body: some View {
        let ink = look.welcome.ink, halo = look.welcome.halo
        ZStack(alignment: .topLeading) {
            Path { $0.move(to: from); $0.addLine(to: callout.end) }.trim(from: 0, to: line)
                .stroke(ink, style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                .shadow(color: halo, radius: 1.5)
            Circle().fill(ink).frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(halo, lineWidth: 1.5).padding(-1.5))
                .scaleEffect(dot ? 1 : 0.2).opacity(dot ? 1 : 0)
                .position(from)
            CalloutLabel(callout: callout)
                .frame(width: 0, height: 0, alignment: callout.side.alignment)
                .offset(callout.side.gap)
                .offset(label || reduceMotion ? .zero : callout.side.lift)
                .opacity(label ? 1 : 0)
                .position(callout.end)
        }
        .onAppear {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.25)) { (dot, line, label) = (true, 1, true) }
                return
            }
            withAnimation(.spring(duration: 0.3, bounce: 0.3).delay(delay)) { dot = true }
            withAnimation(.easeInOut(duration: 0.4).delay(delay + 0.12)) { line = 1 }
            withAnimation(.spring(duration: 0.35, bounce: 0).delay(delay + 0.42)) { label = true }
        }
    }
}

/// The label: its words and its keys, as keycaps, on a solid capsule that reads over any part of the shot.
private struct CalloutLabel: View {
    let callout: Callout
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 6) {
            Text(callout.label).font(.system(size: 12, weight: .semibold))
            ForEach(callout.keys, id: \.self) { key in
                Text(key).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18)
                    .background(.quaternary, in: .rect(cornerRadius: 4))
            }
        }
        .padding(.leading, 10).padding(.trailing, callout.keys.isEmpty ? 10 : 5).frame(height: 26)
        .background(look.cardSolid(), in: .capsule)
        .overlay(Capsule().strokeBorder(look.divider, lineWidth: 0.5))
        .shadow(color: look.welcome.halo, radius: 6, y: 2)
        .fixedSize()
    }
}
