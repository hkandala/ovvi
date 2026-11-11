import AppKit

enum PluginLog {
    nonisolated static let folder = Registry.testConfig
        .map { URL(filePath: $0).appending(path: "logs/plugins") }
        ?? URL.homeDirectory.appending(path: "Library/Logs/\(Registry.logs)/plugins")
    private nonisolated static let queue = DispatchQueue(label: "dev.ovvi.app.plugin-log")

    nonisolated static func file(_ id: String) -> URL {
        folder.appending(path: "\(id).log")
    }

    nonisolated static func add(_ id: String, _ text: String, output: String) {
        add(id, "\(text):\n\(output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    nonisolated static func add(_ id: String, _ text: String) {
        // Indented, so a page's line breaks never read as the app's own lines.
        let text = text.replacingOccurrences(of: "\n", with: "\n  ")
        let line = Data("\(Date.now.ISO8601Format(.iso8601(timeZone: .current))) \(text)\n".utf8)
        queue.async {
            let file = PluginLog.file(id), files = FileManager.default
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
            // ponytail: starts over past 1 MB; keep a second file if authors need more history.
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            if size.map({ $0 > 1 << 20 }) ?? true {
                files.createFile(atPath: file.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: file) else { return }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        }
    }

    /// On the queue: after the lines on their way.
    nonisolated static func show(_ id: String) {
        queue.async {
            let file = PluginLog.file(id)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
            }
            DispatchQueue.main.async { NSWorkspace.shared.open(file) }
        }
    }
}
