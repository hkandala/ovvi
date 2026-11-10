import SwiftUI

/// The intro's steps: the mark's outlines draw on, they fill charcoal → gray → pearl, the name writes on, then the
/// mark's pearl pane grows into the first scene's pane (`scene`).
enum Intro: Comparable {
    case start, outline, fill, name, scene
}

/// The logo (resources/branding, measured on the 1254 px original): three rounded rectangles of 560 × 395 units,
/// each 13 units clear of the one in front, stepping down to the right. Placed in the panel's points.
enum Mark {
    static let unit: CGFloat = 0.23
    /// Centred across the panel, a little above its middle with the name below.
    static let origin = CGPoint(x: (Welcome.size.width - 781 * unit) / 2, y: 196)
    static let offsets = [CGPoint.zero, CGPoint(x: 114, y: 135), CGPoint(x: 221, y: 269)]
    static let radius = 62 * unit, gutter = 13 * unit
    static let size = CGSize(width: 560 * unit, height: 395 * unit)

    /// Pane `index`'s frame in the panel (0 is the back one).
    static func rect(_ index: Int) -> CGRect {
        CGRect(origin: CGPoint(x: origin.x + offsets[index].x * unit, y: origin.y + offsets[index].y * unit),
               size: size)
    }

    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    static func fill(_ index: Int) -> LinearGradient {
        LinearGradient(colors: Look.mark[index], startPoint: .top, endPoint: .bottom)
    }

    /// The thin line the outlines draw with, then the pane's rim once it is filled.
    static func line(drawing: Bool) -> Color {
        .primary.opacity(drawing ? 0.55 : 0.12)
    }
}

/// The mark's back and middle panes and the name; the pearl pane in front is the scene's first pane
/// (`WelcomeScene`), so it can grow into it.
struct MarkBack: View {
    let intro: Intro
    let reduceMotion: Bool
    @Environment(\.look) private var look

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0 ..< 2) { index in
                pane(index)
            }
            name
        }
        .frame(width: Welcome.size.width, height: Welcome.size.height, alignment: .topLeading)
        .opacity(intro == .scene || reduceMotion && intro == .start ? 0 : 1)
        .animation(.easeOut(duration: reduceMotion ? 0.5 : 0.3), value: intro)
    }

    private func pane(_ index: Int) -> some View {
        let rect = Mark.rect(index), front = Mark.rect(2), gone = intro == .scene && !reduceMotion
        // Each pane sits 13 units clear of the one in front of it: the gutter is cut out of it.
        let cut = Mark.rect(index + 1).insetBy(dx: -Mark.gutter, dy: -Mark.gutter).offsetBy(dx: -rect.minX,
                                                                                            dy: -rect.minY)
        return ZStack {
            Mark.shape.fill(Mark.fill(index)).opacity(intro >= .fill || reduceMotion ? 1 : 0)
                .animation(.easeOut(duration: 0.45).delay(0.12 * Double(index)), value: intro >= .fill)
            Mark.shape.trim(from: 0, to: intro >= .outline || reduceMotion ? 1 : 0)
                .stroke(Mark.line(drawing: intro < .fill), lineWidth: 1)
                .animation(.easeInOut(duration: 0.6).delay(0.14 * Double(index)), value: intro >= .outline)
                .animation(.easeOut(duration: 0.5), value: intro >= .fill)
        }
        .frame(width: rect.width, height: rect.height)
        .shadow(color: .primary.opacity(look.dark ? 0 : 0.12), radius: 5, y: 2)
        .mask {
            Path { path in
                path.addRect(CGRect(x: -20, y: -20, width: rect.width + 40, height: rect.height + 40))
                path.addRoundedRect(in: cut, cornerSize: CGSize(width: Mark.radius + Mark.gutter,
                                                                height: Mark.radius + Mark.gutter))
            }
            .fill(style: FillStyle(eoFill: true))
        }
        // At the scene they slide in under the pearl pane and are gone.
        .offset(x: gone ? front.minX : rect.minX, y: gone ? front.minY : rect.minY)
        .scaleEffect(gone ? 0.9 : 1, anchor: .topLeading)
        .animation(.smooth(duration: 0.45), value: gone)
    }

    /// "Ovvi", written on from left to right by a soft-edged mask.
    private var name: some View {
        let width: CGFloat = 140, edge: CGFloat = 40, shown = intro >= .name || reduceMotion
        return Text("Ovvi").font(.system(size: 46, weight: .semibold)).tracking(-0.7).fixedSize()
            .frame(width: width)
            .mask(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle().frame(width: width)
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: edge)
                }
                .offset(x: shown ? 0 : -width - edge)
                .animation(.easeInOut(duration: 0.75), value: shown)
            }
            .offset(x: (Welcome.size.width - width) / 2, y: Mark.rect(2).maxY + 20)
            .offset(y: intro == .scene && !reduceMotion ? -6 : 0)
            .accessibilityHidden(true)
    }
}
