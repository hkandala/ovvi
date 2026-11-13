import HerdrKit

extension HostStore {
    /// While a visible window shows the session: each root's git files are watched (`GitStatus.watch`, the same on
    /// every machine), and every root is read again each 60 s, which covers what a watch cannot see (a root that
    /// became a repository, a watch that ended).
    func followGit() async {
        gitFollowers += 1
        repeat {
            // Watches that ended or found no repository start again on this pass only, never on each snapshot.
            for root in gitEnded {
                gitWatches.removeValue(forKey: root)?.cancel()
            }
            gitEnded = []
            await updateGit(all: true)
        } while await (try? Task.sleep(for: .seconds(60))) != nil
        gitFollowers -= 1
        if gitFollowers == 0 {
            gitWatches.values.forEach { $0.cancel() }
            (gitWatches, gitEnded) = ([:], [])
        }
    }

    /// `all`: every root; else only new and changed roots (after a snapshot), or `only` (its files changed).
    func updateGit(all: Bool, root only: String? = nil) async {
        guard onScreen, await gitUsable.value else { return }
        for workspace in workspaces {
            guard onScreen, !Task.isCancelled else { return }
            let root = root(of: workspace)
            guard let root, only.map({ $0 == root }) ?? (all || root != workspace.gitRoot) else { continue }
            // A change waits for a read already running, which may have started before it.
            while !all, gitReads.contains(workspace.id), !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !gitReads.contains(workspace.id) else { continue }
            workspace.gitRoot = root
            gitReads.insert(workspace.id)
            // One after another: 30 workspaces are not 30 git processes at once.
            workspace.git = await GitStatus.of(root, exec: machine.exec())
            gitReads.remove(workspace.id)
        }
        let roots = Set(workspaces.filter { $0.git != nil }.compactMap(\.gitRoot))
        for (root, watch) in gitWatches where !roots.contains(root) {
            watch.cancel()
            gitWatches[root] = nil
            gitEnded.remove(root)
        }
        for root in roots where gitWatches[root] == nil && gitFollowers > 0 {
            watchGit(root)
        }
    }

    private func watchGit(_ root: String) {
        gitWatches[root] = Task { [weak self] in
            if let exec = await self?.machine.exec(), let changes = await GitStatus.watch(root, exec: exec) {
                for await _ in changes {
                    await self?.updateGit(all: false, root: root)
                }
            }
            if !Task.isCancelled {
                self?.gitEnded.insert(root)
            }
        }
    }
}
