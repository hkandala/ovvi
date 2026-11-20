import HerdrKit

extension PaneLabel {
    /// What a terminal client of herdr shows for a card: one line with the plugin's name, fixed for the process, so a
    /// label change asks nothing of it (a change of plugin makes a new pane). `stty raw` makes Ctrl-C and Ctrl-D plain
    /// bytes for the `cat` that swallows them. herdr runs the argv itself, with no shell quoting.
    var placeholder: [String] {
        ["sh", "-c", #"""
        T="$1 shown in Ovvi"
        draw() {
          set -- $(stty size 2>/dev/null || echo "24 80")
          x=$(( ($2 - ${#T}) / 2 + 1 )); [ $x -lt 1 ] && x=1
          printf '\033[?25l\033[2J\033[%d;%dH\033[2m%s\033[0m' $(( $1 / 2 )) "$x" "$T"
        }
        stty raw -echo 2>/dev/null
        trap draw WINCH
        draw
        # Through fd 3: dash gives a background job /dev/null as its stdin.
        exec 3<&0
        cat <&3 >/dev/null &
        while kill -0 $! 2>/dev/null; do wait $!; done
        """#, "sh", (manifest?.name ?? plugin).shown]
    }
}

extension HostStore {
    /// herdr starts a fresh shell under the label after a restart, and a pane labeled outside the app has no
    /// placeholder.
    func keepPlaceholder(_ pane: Pane) {
        guard let label = pane.plugin, let program = pane.program, let client else { return }
        guard program.isShell else {
            // A slow shell startup after a restart can outlast the first look: one more, later.
            if !program.isPlaceholder, pane.rechecked != pane.terminalID {
                pane.rechecked = pane.terminalID
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    await askProgram(pane.id)
                }
            }
            return
        }
        guard let shell = program.foreground.first?.pid, pane.placed != shell else { return }
        pane.placed = shell
        // Base64, which any login shell passes on. ⌃U goes as a key: herdr pastes text into a shell that turned
        // bracketed paste on (zsh, bash 5.1+, fish at their prompt), where a ⌃U in it is a plain character. The space
        // keeps the line out of a history that ignores such lines (fish; zsh and bash when set to).
        let line = " exec " + shellEnvelope(["exec"] + label.placeholder)
        Task {
            try? await client.sendKeys(["ctrl+u"], pane: pane.id)
            try? await client.sendInput(line, keys: ["enter"], pane: pane.id)
        }
    }
}
