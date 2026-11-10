import Foundation
import HerdrKit

extension HostStore {
    /// A `cd` sends no herdr event, so the snapshot's cwd may be stale.
    func newTab(in workspaceID: String, cwd: String?, of paneID: String?) async -> HerdrKit.Pane? {
        var cwd = cwd
        if let paneID, let fresh = try? await client?.pane(paneID).cwd {
            cwd = fresh
        }
        var created: HerdrKit.Pane?
        await write { created = try await $0.newTab(workspace: workspaceID, cwd: cwd ?? "~") }
        return created
    }

    func newWorkspace(label: String?, cwd: String, fixed: Bool) async -> HerdrKit.Pane? {
        let fixed = fixed && !Chooser.asked
        var created: HerdrKit.Pane?
        // Ahead of the snapshot that shows it, so its first frame has the chooser.
        await write {
            created = try await $0.newWorkspace(label: label, cwd: cwd)
            choose(created, fixed: fixed)
        }
        return created
    }

    func rename(tab tabID: String, label: String) async {
        let label = label.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty,
              label != tab(tabID)?.label else { return }
        await write { try await $0.rename(tab: tabID, label: label) }
    }

    func rename(workspace workspaceID: String, label: String) async {
        let label = label.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, label != workspaces.first(where: { $0.id == workspaceID })?.label else { return }
        await write { try await $0.rename(workspace: workspaceID, label: label) }
    }

    @discardableResult
    func write(_ action: (any Multiplexer) async throws -> Void) async -> Bool {
        guard client != nil else { return false }
        do {
            try await request { client in
                // A new write can make an old error untrue; other notices keep their time.
                if notice?.tone == .error {
                    notice = nil
                }
                try await action(client)
            }
            return true
        } catch {
            show(Notice(text: error.localizedDescription))
            return false
        }
    }

    /// A snapshot read follows a failure too: part of the write may have happened (Close Other Tabs).
    func request<T>(_ action: (any Multiplexer) async throws -> T) async throws -> T {
        guard let client else { throw HerdrError.failed("Ovvi is not connected to herdr session \(session)") }
        await writes.enter()
        let result: Result<T, Error>
        do {
            result = try await .success(action(client))
        } catch {
            result = .failure(error)
        }
        writes.leave()
        await client.refresh()
        return try result.get()
    }

    /// The 10 s refresh skips the workspace meanwhile (`gitReads`), so no stale read lands after this one.
    func sync(_ workspace: Workspace, _ sync: Git.Sync) async {
        guard let root = workspace.gitRoot else { return }
        gitReads.insert(workspace.id)
        defer { gitReads.remove(workspace.id) }
        let exec = await machine.exec()
        let word = sync.rawValue.capitalized
        let running = Notice(text: "\(word)ing \(workspace.label)…", tone: .progress)
        notice = running
        var done = Notice(text: "\(word)ed \(workspace.label)", tone: .success)
        do {
            try await Git.run(root, sync.arguments, exec: exec)
        } catch {
            // The notice shows two lines: git's error comes last, after its hints.
            let lines = error.localizedDescription.split(separator: "\n").filter { !$0.hasPrefix("hint:") }
            done = Notice(text: lines.suffix(2).joined(separator: "\n"))
        }
        workspace.git = await GitStatus.of(root, exec: exec)
        let failed = done.tone == .error
        if failed || notice?.id == running.id {
            show(done, for: .seconds(failed ? 4 : 2))
        }
    }

    func notFound(_ path: String) {
        let shown = MachinePath.short(path, remote: machine.isRemote)
        show(Notice(text: "File not found: \(shown)", tone: .warning))
    }

    /// Waits for the write ahead of it, so the last writer wins on a slow machine too, and skips a closed pane: its
    /// device removes the file.
    func saveState(_ saving: inout Task<Void, Never>?, path: String, data: Data, terminalID: String) {
        saving?.cancel()
        let previous = saving
        saving = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await previous?.value
            guard !Task.isCancelled, let self, terminalPane(terminalID) != nil else { return }
            await machine.exec().write(home: path, String(decoding: data, as: UTF8.self))
        }
    }

    func show(_ new: Notice, for time: Duration = .seconds(4)) {
        notice = new
        Task {
            try? await Task.sleep(for: time)
            if notice?.id == new.id {
                notice = nil
            }
        }
    }
}

extension HostStore {
    /// On This Mac, `/usr/bin/git` without the developer tools opens their install dialog. A remote machine without
    /// git fails harmlessly.
    func gitRuns() async -> Bool {
        if machine.isRemote {
            return true
        }
        return await gitUsable.value
    }
}

/// ponytail: `updateGit` uses This Mac's check for remote machines too; ask each machine when one lacks git.
let gitUsable = Task { await GitStatus.usable(exec: localExec.value) }
