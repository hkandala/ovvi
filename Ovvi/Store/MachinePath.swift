import AppKit
import HerdrKit

enum MachinePath {
    /// Links stay: `/private/tmp` is no `/tmp`.
    static func tidy(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") where part != "." {
            if part == ".." {
                _ = parts.popLast()
            } else {
                parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// A remote machine's home is where macOS and Linux put it, any user's. ponytail: another user's home and one
    /// elsewhere read wrong; ask the machine for its home once if that matters.
    static func short(_ path: String, remote: Bool) -> String {
        guard remote else { return (path as NSString).abbreviatingWithTildeInPath }
        return path.replacing(/^\/(?:Users\/(?!Shared(?:\/|$))|home\/)[^\/]+(?=\/|$)|^\/root(?=\/|$)/, with: "~",
                              maxReplacements: 1)
    }
}

extension HostStore {
    func there(_ path: String, from cwd: String) async -> String? {
        let script = #"""
        case $1 in "~"|"~/"*) p=$HOME${1#"~"} ;; /*) p=$1 ;; *) p=${2:-$HOME}/$1 ;; esac
        if [ -d "$p" ]; then printf '%s/' "$p"; elif [ -e "$p" ]; then printf '%s' "$p"; fi
        """#
        let found = await (try? machine.exec().output(["sh", "-c", script, "sh", path, cwd])) ?? ""
        return found.isEmpty ? nil : MachinePath.tidy(found) + (found.hasSuffix("/") ? "/" : "")
    }

    func folder(_ typed: String, from base: String) async -> String? {
        let script = #"cd -- "$2" 2>/dev/null; case $1 in "~"|"~/"*) set -- "$HOME${1#\~}";; esac; "#
            + #"cd -- "$1" 2>/dev/null && pwd -P"#
        guard let channel = try? await machine.exec().run(["sh", "-c", script, "sh", typed, base]) else { return nil }
        channel.closeInput()
        let path = await channel.lines.reduce("", +)
        return await channel.exit().status == 0 && path.hasPrefix("/") ? path : nil
    }

    func chooseFolder(from start: String, in window: NSWindow) async -> String? {
        if !machine.isRemote {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.directoryURL = URL(filePath: (start as NSString).expandingTildeInPath)
            guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return nil }
            let path = url.path(percentEncoded: false)
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        let alert = NSAlert()
        alert.messageText = "Go to Folder"
        alert.informativeText = "A folder on \(machine.name)"
        let field = NSTextField(string: start)
        field.frame.size.width = 280
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return nil }
        guard let path = await folder(field.stringValue, from: start) else {
            show(Notice(text: "No folder \(field.stringValue)", tone: .warning))
            return nil
        }
        return path
    }
}
