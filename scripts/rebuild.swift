// Ovvi Dev's Rebuild (Settings ▸ General) runs this from the repo the app was built from, as
// `swift <repo>/scripts/rebuild.swift <app pid> <app path>`. It shows make install's log in a window of its own, prints
// a line once that window shows (the app then quits), runs make install once the app is gone, and on success opens the
// app again and ends. On failure it stays on the log.
import AppKit

@MainActor
final class Rebuild: NSObject, NSApplicationDelegate {
    let pid: pid_t, app: URL
    let build = Process()
    let scroll = NSTextView.scrollableTextView()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 440),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
                          defer: false)

    init(pid: pid_t, app: URL) {
        self.pid = pid
        self.app = app
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.applicationIconImage = NSWorkspace.shared.icon(forFile: app.path)
        NSApp.mainMenu = menu()
        if let log = scroll.documentView as? NSTextView {
            log.isEditable = false
            log.textContainerInset = NSSize(width: 10, height: 10)
        }
        let name = app.deletingPathExtension().lastPathComponent
        window.title = "Rebuilding \(name)"
        window.subtitle = FileManager.default.currentDirectoryPath
        window.contentView = scroll
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        // Over the app's windows, which have the focus until the app quits.
        window.orderFrontRegardless()
        NSApp.activate()
        append("Waiting for \(name) to quit…\n")
        print("shown")
        fflush(stdout)
        // The app's quit saves its windows first; make install replaces it only once it is gone.
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard kill(self.pid, 0) != 0 else { return }
                timer.invalidate()
                self.run()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_: Notification) {
        if build.isRunning {
            build.terminate()
        }
    }

    func run() {
        append("$ make install\n")
        let output = Pipe()
        build.executableURL = URL(filePath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        // A login shell gets a terminal's PATH: the app's has no Homebrew or node.
        build.arguments = ["-lic", "make install"]
        // xcbeautify and npm print colors into a pipe too.
        build.environment = ProcessInfo.processInfo.environment.merging(["NO_COLOR": "1"]) { $1 }
        build.standardInput = FileHandle.nullDevice
        build.standardOutput = output
        build.standardError = output
        // Done when make ended and its last output is in the log.
        let done = DispatchGroup()
        done.enter()
        done.enter()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return done.leave()
            }
            DispatchQueue.main.async { self.append(String(decoding: data, as: UTF8.self)) }
        }
        build.terminationHandler = { _ in done.leave() }
        do {
            try build.run()
        } catch {
            append("Could not start \(build.executableURL?.path ?? "the shell"): \(error.localizedDescription)\n")
            return failed()
        }
        done.notify(queue: .main) {
            MainActor.assumeIsolated { self.finish() }
        }
    }

    func finish() {
        guard build.terminationStatus == 0 else {
            append("\nmake install failed with exit status \(build.terminationStatus).\n")
            return failed()
        }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            let problem = error?.localizedDescription
            DispatchQueue.main.async {
                guard let problem else { return NSApp.terminate(nil) }
                self.append("\nCould not open \(self.app.path): \(problem)\n")
                self.failed()
            }
        }
    }

    func failed() {
        window.title = "Rebuild Failed"
        NSApp.requestUserAttention(.criticalRequest)
    }

    func append(_ text: String) {
        guard let log = scroll.documentView as? NSTextView else { return }
        log.textStorage?.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.textColor,
        ]))
        log.scrollToEndOfDocument(nil)
    }

    /// Quit, and Copy and Select All for the log.
    func menu() -> NSMenu {
        let menu = NSMenu()
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let all = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        for (title, items) in [("Rebuild", [quit]), ("Edit", [copy, all])] {
            let submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
        }
        return menu
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3, let pid = pid_t(arguments[1]) else {
    FileHandle.standardError.write(Data("usage: swift scripts/rebuild.swift <app pid> <app path>\n".utf8))
    exit(2)
}

// stdout is a pipe to the app, which quits.
signal(SIGPIPE, SIG_IGN)
MainActor.assumeIsolated {
    let rebuild = Rebuild(pid: pid, app: URL(filePath: arguments[2]))
    NSApplication.shared.delegate = rebuild
    NSApp.setActivationPolicy(.regular)
    withExtendedLifetime(rebuild) { NSApp.run() }
}
