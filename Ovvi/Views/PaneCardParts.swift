import HerdrKit
import SwiftUI

extension Page {
    /// `make` false: only one made already (a kept page out of view must not make again a card the registry dropped).
    /// ponytail: a hidden card holds a dropped card's web view until its next body, usually the next snapshot; make the
    /// registry observed if that wait matters.
    func cards(_ pane: HostStore.Pane?, make: Bool) -> (Browser?, Plugin?) {
        guard make else {
            let id = pane?.terminalID ?? ""
            return (terminals.browsers[id], terminals.plugins[id])
        }
        return (pane.flatMap(browser), pane.flatMap(plugin))
    }

    func twoRows(_ pane: HostStore.Pane?) -> Bool {
        guard let pane, !floats(pane), store.chooser(pane.id) == nil else { return false }
        guard let label = pane.plugin else { return pane.agent != nil || store.adapter(pane) != nil }
        return label.manifest.map { plugin in
            plugin.entry == nil || plugin.hasRow
        } ?? false
    }

    func headerHeight(_ pane: HostStore.Pane?) -> CGFloat {
        guard let pane, twoRows(pane) else { return PaneCard.header }
        guard pane.plugin != nil else { return PaneCard.header + PaneCard.row }
        let rest = (PaneCard.header - PaneCard.row) / 2
        return PaneCard.header + PaneCard.row + rest + (pane.browser != nil ? PaneCard.floatingTop : 0)
    }
}

struct CardPicture: View {
    let picture: CGImage
    let pane: HostStore.Pane

    var body: some View {
        let browser = pane.browser != nil, inset = browser ? 6 : pane.plugin != nil ? PaneCard.inset : 0
        Image(decorative: picture, scale: 1).resizable()
            .clipShape(.rect(cornerRadius: browser ? 6 : 0))
            .padding([.horizontal, .bottom], inset)
    }
}

/// From the window's layers at its place: `cacheDisplay` draws SwiftUI's content blank. ponytail: the deepest layer
/// holding the place is the rows' (the reply box is a sibling, so it is not in the picture); find SwiftUI's card layer
/// if that matters.
struct ChatProbe: NSViewRepresentable {
    let terminalID: String
    let registry: PaneViewRegistry
    let hidden: Bool

    func makeNSView(context _: Context) -> Probe {
        let probe = Probe()
        registry.chatViews[terminalID] = { [weak probe] in
            // Not one already out of view: a blank picture, or the page over it, would replace a good one.
            guard let probe, !probe.outOfView, let root = probe.window?.contentView?.superview?.layer,
                  !probe.visibleRect.isEmpty else { return nil }
            let rect = probe.convert(probe.bounds, to: nil)
            guard let context = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height),
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
            // The deepest layer that holds the chat's place (its rows, under 1 ms), not the window's (120 ms).
            var layer = root, area = rect
            while let next = layer.sublayers?
                .last(where: { !$0.isHidden && $0.opacity > 0 && $0.frame.contains(area) })
            {
                area = next.convert(area, from: layer)
                layer = next
            }
            if layer.contentsAreFlipped() {
                context.translateBy(x: -area.minX, y: area.maxY)
                context.scaleBy(x: 1, y: -1)
            } else {
                context.translateBy(x: -area.minX, y: -area.minY)
            }
            layer.render(in: context)
            return context.makeImage()
        }
        return probe
    }

    func updateNSView(_ probe: Probe, context _: Context) {
        probe.outOfView = hidden
    }

    final class Probe: NSView {
        var outOfView = false
    }
}

struct PaneTitle: View {
    let pane: HostStore.Pane?

    var body: some View {
        let (name, folder) = pane?.header ?? (nil, "terminal")
        let lead = name.map { "\($0) " } ?? ""
        Text("\(lead)\(Text(folder).foregroundStyle(name == nil ? .primary : .secondary))")
            .lineLimit(1)
            .truncationMode(pane?.label != nil ? .tail : name == nil ? .head : .middle)
    }
}

struct FloatedPlaceholder: View {
    let page: Page
    let pane: HostStore.Pane

    var body: some View {
        VStack(spacing: 12) {
            Text("This pane is open in a floating window.").foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("pane.\(pane.id).floating")
            HStack(spacing: gap) {
                Button("Show Window") { page.float(pane) }
                    .accessibilityIdentifier("pane.\(pane.id).show")
                Button("Bring Back Here") {
                    if let terminalID = pane.terminalID {
                        page.floating[terminalID] = nil
                    }
                    page.go(to: pane)
                }
                .accessibilityIdentifier("pane.\(pane.id).back")
            }
            .buttonStyle(.glass)
        }
        .padding(gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
