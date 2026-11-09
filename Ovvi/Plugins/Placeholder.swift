import HerdrKit

extension PaneLabel {
    /// The pane's command in herdr (ui/browser#in-herdrs-tui): the kind's name, the argument without its scheme
    /// (`example.com/a`) and "Shown in Ovvi", centered. A resize, or Ovvi's SIGWINCH after a new label
    /// (`HostStore.redrawPlaceholder`), draws it again with the label's argument as herdr has it now. Keys do nothing:
    /// `stty raw` makes Ctrl-C and Ctrl-D plain bytes for the `cat` that swallows them. herdr runs the argv itself,
    /// with no shell quoting.
    var placeholder: [String] {
        let script = #"""
        relabel() {
          p=$("${HERDR_BIN_PATH:-herdr}" --session "${HERDR_SESSION:-default}" pane get "$HERDR_PANE_ID" 2>/dev/null) &&
            U=$(printf %s "$p" | sed -n 's/.*"label":"ovvi:[^ "]*\( \([^"\\]*\(\\.[^"\\]*\)*\)\)\{0,1\}".*/\2/p' |
              sed 's/\\\(.\)/\1/g')
        }
        draw() {
          set -- $(stty size 2>/dev/null || echo "24 80"); r=$1 c=$2
          printf '\033[?25l\033[2J'
          line() {
            x=$(( (c - ${#2}) / 2 + 1 )); [ $x -lt 1 ] && x=1
            printf '\033[%d;%dH%b%s\033[0m' "$1" "$x" "$3" "$2"
          }
          y=$(( r / 2 - 2 ))
          line $y "$T" '\033[1m'
          [ -n "$U" ] && line $((y + 2)) "${U#*://}" '\033[4;34m'
          line $((y + 4)) "Shown in Ovvi" '\033[2m'
        }
        T=$1 U=$2
        stty raw -echo 2>/dev/null
        trap 'relabel; draw' WINCH
        draw
        # Through fd 3: dash gives a background job /dev/null as its stdin.
        exec 3<&0
        cat <&3 >/dev/null &
        while kill -0 $! 2>/dev/null; do wait $!; done
        """#
        return ["sh", "-c", script, "sh", manifest?.name ?? plugin, arg]
    }
}

extension HostStore {
    /// A browser or plugin pane with only its shell in front gets its placeholder again, typed into that shell once
    /// per shell process (plugins/labels#the-placeholder): herdr starts a fresh shell under the label after a restart,
    /// and a pane labeled outside the app may have none. Never into a pane that runs another program.
    func keepPlaceholder(_ pane: Pane) {
        guard let label = pane.plugin, let program = pane.program, let client else { return }
        guard program.isShell else {
            if program.isPlaceholder {
                redrawPlaceholder(pane, program)
            }
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
        pane.drawnLabel = pane.label
        // In place of the shell, so the pane runs only the placeholder; base64, which any login shell passes on. ⌃U
        // first clears a line half typed in a herdr TUI, as a key: herdr pastes text into a shell that turned
        // bracketed paste on (zsh, bash 5.1+, fish at their prompt), where a ⌃U in it is a plain character. The space
        // keeps the line out of a history that ignores such lines (fish; zsh and bash when set to).
        let line = " exec " + SSHExec.envelope(["exec"] + label.placeholder)
        Task {
            try? await client.sendKeys(["ctrl+u"], pane: pane.id)
            try? await client.sendInput(line, keys: ["enter"], pane: pane.id)
        }
    }

    /// After a new label (a browser's typed address; a label change asks for the program again), the placeholder
    /// draws the label's argument: SIGWINCH to its processes, by pid (its `cat` ignores it; a pid gone stale meanwhile
    /// gets a harmless resize signal). Not one it drew already: a placeholder from before this launch shows its old
    /// argument until its label changes.
    private func redrawPlaceholder(_ pane: Pane, _ program: Program) {
        guard pane.drawnLabel != pane.label, !program.foreground.isEmpty else { return }
        pane.drawnLabel = pane.label
        // Never 0 or -1: `kill` would signal a process group, or every process of the user.
        let pids = program.foreground.filter { $0.pid > 1 }.map { String($0.pid) }
        guard !pids.isEmpty else { return }
        Task { await machine.exec().succeeds(#"kill -WINCH "$@""#, pids) }
    }
}
