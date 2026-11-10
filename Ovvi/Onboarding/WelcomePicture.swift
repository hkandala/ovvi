import ImageIO
import SwiftUI

/// A page's picture: its shots, each framed on the part the words talk about (a slow push-in from a little wider),
/// one soft ring with a small label on that part. A page of more shots steps through them by itself, the camera and
/// the ring gliding to the next part; with Reduce Motion it shows the last, still.
struct WelcomePicture: View {
    let shots: [WelcomeShot]
    let pictures: WelcomePictures
    /// Reduce Motion: the last shot, still.
    let still: Bool
    static let size = CGSize(width: 920, height: 410)
    @State private var step = 0
    @State private var camera: CGRect?
    @State private var ring = CGRect.zero
    @State private var ringShown = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.look) private var look

    var body: some View {
        let size = Self.size, dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack(alignment: .topLeading) {
            ForEach(shots.indices, id: \.self) { index in
                if let (image, _) = pictures.image(shots[index].picture, dark: dark) {
                    Image(decorative: image, scale: 2).resizable().interpolation(.high)
                        .frame(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
                        .opacity(index <= step ? 1 : 0)
                }
            }
        }
        .modifier(Camera(rect: camera ?? Self.wider(shots[0].focus), size: size))
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(shape)
        .overlay {
            Ring(camera: camera ?? Self.wider(shots[0].focus), rect: ring, size: size, label: shots[step].label,
                 shown: ringShown)
        }
        .background(look.cardFill, in: shape)
        .overlay(shape.strokeBorder(look.divider.opacity(0.6), lineWidth: 0.5))
        // The ring's label, and the picture and look it shows (the tests).
        .accessibilityElement().accessibilityAddTraits(.isStaticText).accessibilityIdentifier("welcome.picture")
        .accessibilityLabel(shots[step].label)
        .accessibilityValue(pictures.image(shots[step].picture, dark: dark)
            .map { "\(shots[step].picture) \($0.look)" } ?? "")
        .task { await play() }
    }

    /// The push-in, the ring, then each next shot every 2.8 s.
    private func play() async {
        let last = shots.count - 1
        if still {
            step = last
            camera = Self.fit(shots[last].focus)
            ring = shots[last].ring
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) { ringShown = true }
            return
        }
        ring = shots[0].ring
        withAnimation(.spring(duration: 1.8, bounce: 0)) { camera = Self.fit(shots[0].focus) }
        withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.6)) { ringShown = true }
        for next in shots.indices.dropFirst() {
            do {
                try await Task.sleep(for: .seconds(2.8))
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: 0.6)) { step = next }
            withAnimation(.spring(duration: 1.2, bounce: 0)) {
                camera = Self.fit(shots[next].focus)
                ring = shots[next].ring
            }
        }
    }

    /// The focus grown to the picture's aspect round its centre.
    static func fit(_ focus: CGRect) -> CGRect {
        let aspect = size.width / size.height
        let width = max(focus.width, focus.height * aspect)
        return CGRect(x: focus.midX - width / 2, y: focus.midY - width / aspect / 2, width: width,
                      height: width / aspect)
    }

    /// Where the push-in starts: 12 % wider.
    static func wider(_ focus: CGRect) -> CGRect {
        let rect = fit(focus)
        return rect.insetBy(dx: -rect.width * 0.06, dy: -rect.height * 0.06)
    }
}

/// Puts the camera's rect (window points) on the picture's frame: only a transform, so a push-in never lays out.
private struct Camera: GeometryEffect {
    var rect: CGRect
    let size: CGSize

    var animatableData: CGRect.AnimatableData {
        get { rect.animatableData }
        set { rect.animatableData = newValue }
    }

    func effectValue(size _: CGSize) -> ProjectionTransform {
        let scale = size.width / rect.width
        return ProjectionTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: -rect.minX * scale,
                                                     ty: -rect.minY * scale))
    }
}

/// The ring and its label over the part, where the camera puts it, drawn at the screen's size (never scaled up).
private struct Ring: View, Animatable {
    var camera: CGRect
    var rect: CGRect
    let size: CGSize
    let label: String
    let shown: Bool

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGRect.AnimatableData> {
        get { AnimatablePair(camera.animatableData, rect.animatableData) }
        set { (camera.animatableData, rect.animatableData) = (newValue.first, newValue.second) }
    }

    var body: some View {
        let scale = size.width / camera.width
        let part = CGRect(x: (rect.minX - camera.minX) * scale, y: (rect.minY - camera.minY) * scale,
                          width: rect.width * scale, height: rect.height * scale)
            .insetBy(dx: -3, dy: -3).intersection(CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3))
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        // On the ring's top edge, as a tab; inside it at the picture's top.
        let top = part.minY >= 12 ? part.minY - 10 : part.minY + 6
        ZStack(alignment: .topLeading) {
            ZStack {
                shape.stroke(Color.accentColor.opacity(0.22), lineWidth: 6)
                shape.stroke(Color.accentColor, lineWidth: 2)
            }
            .frame(width: part.width, height: part.height).scaleEffect(shown ? 1 : 1.06)
            .offset(x: part.minX, y: part.minY)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Look.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3).background(Color.accentColor, in: .capsule)
                .contentTransition(.opacity).fixedSize()
                .offset(x: part.minX + 12, y: top)
        }
        .opacity(shown ? 1 : 0)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The pictures, decoded off the main thread before they show: a 2880 × 1800 HEIC took a frame or two to decode.
/// Only the pages in view and next are kept.
@MainActor @Observable
final class WelcomePictures {
    private var images: [String: CGImage] = [:]

    /// The picture in this look, else in the other until this one is decoded (the appearance just changed).
    func image(_ picture: String, dark: Bool) -> (image: CGImage, look: String)? {
        let looks = dark ? ["dark", "light"] : ["light", "dark"]
        return looks.lazy.compactMap { look in self.images["\(picture)-\(look)"].map { ($0, look) } }.first
    }

    /// Decodes the missing ones, then lets go of the others.
    func keep(_ names: Set<String>) async {
        for name in names.sorted() where images[name] == nil {
            images[name] = await Task.detached(priority: .userInitiated) { Self.decode(name) }.value
        }
        // A newer page's call may run: only the latest lets go.
        guard !Task.isCancelled else { return }
        images = images.filter { names.contains($0.key) }
    }

    private nonisolated static func decode(_ name: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: "welcome-\(name)", withExtension: "heic"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}
