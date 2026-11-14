import AppKit
import GhosttyTerminal
import HerdrKit
import UniformTypeIdentifiers

/// A pane drag carries none of these types, so that it goes on to the card's drop zones.
extension PaneSurfaceView {
    /// libghostty-spm registers files, images, links and text itself.
    static let dropTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    override func draggingEntered(_: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    /// libghostty-spm's own refuses a drag that carries only a file promise.
    override func draggingUpdated(_: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        var urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
        if urls.isEmpty, let image = Self.savedImage(board) {
            urls = [image]
        }
        if !urls.isEmpty {
            return drop(urls)
        }
        // ponytail: each promised file pastes on its own; join them when a source promises several.
        let promises = board.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]
        guard let promise = promises?.first, let folder = Self.newFolder() else {
            return super.performDragOperation(sender)
        }
        promise.receivePromisedFiles(
            atDestination: folder,
            options: [:],
            operationQueue: .main,
            reader: { [weak self] url, error in
                guard error == nil else { return }
                MainActor.assumeIsolated { _ = self?.drop([url]) }
            },
        )
        return true
    }

    private func drop(_ urls: [URL]) -> Bool {
        guard let store = store(), store.machine.isRemote else {
            return paste(text: urls.map { Self.escaped(Self.reachable($0).path(percentEncoded: false)) }
                .joined(separator: " "))
        }
        Task {
            let exec = await store.machine.exec()
            do {
                var paths: [String] = []
                for url in urls {
                    try await paths.append(Self.escaped(exec.upload(url)))
                }
                _ = paste(text: paths.joined(separator: " "))
            } catch {
                store.show(Notice(text: error.localizedDescription))
            }
        }
        return true
    }

    /// Ghostty's `Shell.escape` (libghostty-spm's copy is internal), plus `^`, a glob under zsh's `EXTENDED_GLOB`. A
    /// no-break space (U+202F in a screenshot's name) splits no word: it stays as it is. A path with a line break is
    /// quoted instead: a shell without bracketed paste would run the line after it.
    private static func escaped(_ path: String) -> String {
        if path.contains(where: \.isNewline) {
            return path.shellQuoted
        }
        return path.unicodeScalars.reduce(into: "") { text, scalar in
            if "\\ ()[]{}<>\"'`!#$&;|*?^\t".unicodeScalars.contains(scalar) {
                text += "\\"
            }
            text.unicodeScalars.append(scalar)
        }
    }

    /// macOS lets only the app that made a file in a `TemporaryItems` folder and the drop's receiver read it, not the
    /// pane's programs (herdr's server runs them). A screenshot's floating thumbnail drops a file there, as any app's
    /// `itemReplacementDirectory` does.
    private static func reachable(_ url: URL) -> URL {
        guard url.pathComponents.contains("TemporaryItems"),
              let copy = newFolder()?.appending(path: url.lastPathComponent),
              (try? FileManager.default.copyItem(at: url, to: copy)) != nil
        else { return url }
        return copy
    }

    /// Not `NSImage(pasteboard:)`, which would load a dragged web link.
    private static func savedImage(_ board: NSPasteboard) -> URL? {
        guard let type = board
            .availableType(from: [.png, .tiff] + [UTType.jpeg, .gif, .webP].map { .init($0.identifier) }),
            let data = board.data(forType: type),
            let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]),
            let file = newFolder()?.appending(path: "image.png")
        else { return nil }
        return (try? png.write(to: file)).map { file }
    }

    /// `$TMPDIR`: only the user reads it, and the system's cleanup of temporary files removes it.
    private static func newFolder() -> URL? {
        let folder = URL.temporaryDirectory.appending(path: "ovvi-\(UUID().uuidString)")
        return (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true))
            .map { folder }
    }
}

extension Page {
    /// ponytail: Go to Directory is This Mac's only (its command is off on a remote machine); a remote one needs
    /// another picker.
    func choosePath(directory: Bool) async {
        guard let pane = keyboardPane, let client = store.client, let window = NSApp.keyWindow else { return }
        let remote = store.machine.isRemote
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory || !remote
        panel.canChooseFiles = !directory
        if !remote {
            panel.directoryURL = await (try? client.pane(pane.id).cwd).map { URL(filePath: $0) }
        }
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
        var path = url.path(percentEncoded: false)
        do {
            if remote, !directory {
                path = try await store.machine.exec().upload(url)
            }
            if directory, try await client.program(pane.id)?.isShell != true {
                store.show(Notice(text: "A program is running in the pane", tone: .warning))
                return
            }
        } catch {
            store.show(Notice(text: error.localizedDescription))
            return
        }
        await store.write { client in
            try await client.sendInput(
                directory ? "cd -- \(path.shellQuoted)" : path.shellQuoted,
                keys: directory ? ["enter"] : [],
                pane: pane.id,
            )
        }
    }
}
