# Phase 57: Nineteenth feedback: empty states, a simpler sidebar, cards that survive idle

Goal: the fixes from the user's nineteenth round:

- Every empty, connecting and loading state is designed, and Ovvi can install herdr.
- One sidebar: Pinned tabs, workspaces that unfold to their agents, Archived Sessions. No Agents view.
- ⌘- and ⌥-click links act and look the same everywhere; HTML files open in the browser.
- Browser and Markdown cards survive a long idle; the remote browser stays up.
- Relaunch with Chat works again; a key redraws a terminal's TUI.
- The chat view shows times and ticks.
- Small keys and padding fixes.

The user's words are quoted; the decisions under them are the orchestrator's. Screenshots in `.build/fb57/` (not
committed):

| File | Shows |
|---|---|
| `5.18.41.png` | a TUI with `[warn] kq_dispatch: skipping fd=… errno=9` lines drawn over its input box |
| `6.01.48.png` | the chat bubble look wanted: time and a double tick at the bottom right |
| `6.23.38.png`, `6.23.46.png`, `6.23.55.png` | Browser, File Explorer and Git in floating windows, their bars close to the top edge |

Tracks run in parallel and push straight to main after review and green chosen tests. The phase ends with two full
runs and on-demand on the final head.

## Track A: empty states, loaders, installing herdr, ⌘N (items 1, 12)

1. "can we improve the empty state better, when no session connected, when session connected but no workspaces, when
   connecting to ssh, improve the loaders etc, for empty state use icons where relevant, revamp the ui overall with
   empty state, and also when no herdr is installed, we should provide an option to install herdr, which basically
   uses the default installation command from herdr docs and set it up on users device or sshed machine, look through
   all cases, empty states etc and improve them. show me before and after pictures for all empty states once done"
12. "when i click cmd+n which opens a new window, it by default connects to mac herdr session, it shouldn't instead
    show machienes and their sessions as options to connect to, again this empty state should be improved as part of
    the empty state improvement i mentioned"
   - First an inventory of every empty, connecting, loading and failed state (window, sidebar, tab strip, cards,
     panels, Settings), with a before picture of each, dark and light.
   - One empty-state look: an SF Symbol, a title, one line, at most two buttons. One loader look.
   - Install herdr uses the command from herdr's docs, on This Mac or over SSH, shows its progress and then connects.
   - ⌘N opens a window that shows the machines and their sessions to pick from; it connects to nothing by itself.
   - After pictures of every state, dark and light.

## Track B: one simpler sidebar (item 2)

2. "so on the agent sidebar few more changes, let's have new agent button at top, let's remove concept of settled, it
   doesn't make much sense to me, and when sorting i know we are sorting by recency, but i kinda feel we should have
   workspace view as well, which we removed now, but this new workspace grouping should be simpler, we should show
   workspaces like how we show in regular workspaces but we show agents under it, keep the agents more like just one
   line, showing title and its logo, i am even thinking we should probably remove that agents view button and put
   some option within regular sidebar to flip between two views, so one view is only workspaces no archived or
   anything, basically clean herdr like view, then next view is just exactly like herdr but we show agents list
   within each workspace, actually let's do one thing, so herdr like sidebar, add small arrow button at the right to
   each worksapce, clicking on it expands and shows all list of agents, just showing logo and title, and within that
   workspace sorting should be based on recently updated ones, expand the glass button covering the expanded agents as
   well, and let's show archived section at the bottom all the time, so basically no switching view, same workspaces
   with archived, and each workspace can be expande to show all agents runing in it sorted by recently updated. let's
   remove other view where only agents are shown. i am trying to simplify the sidebar overall. give me an ui mockup of
   this first, oh pinned section should be there at top, where you can pin certain tabs, so pinning is based on tab,
   and show tab name, so remove the pinning icon to the agents, and let's have an option of pin icon on hovering tab
   pill or right clicking on tab pill, also for agent sessions with no titles, let's shwo the first user prompt for
   the session, like show may be 100 chars of it with ... or something like that, and archived and pinned sections
   should stck to bottom and top respectively with the middle section scrollable, and at the bottom remove the dots
   indicating sessions for now. so archvied stays at the bottom above filter, also let's call it Archived Sessions to
   be clear"
   - A mockup first (HTML in `~/Downloads/ovvi-research/`), dark and light; build after the user's go.
   - Pinned tabs on top (sticky), workspaces in the middle (scrolls), each with a chevron that unfolds its agents, one
     line each (logo and title, newest change first) inside the row's glass; Archived Sessions sticky at the bottom
     above the filter. New Agent button at the top. No Agents view, no Settled, no session dots.
   - Pin and Unpin on a tab pill's hover and its context menu, not on agents.
   - An untitled session shows its first prompt, cut at 100 characters with "…".

## Track C: links the same everywhere, HTML in the browser (items 3, 4, 14)

3. "one more thing i noticed is on holding cmd and hovering over a link on a terminal underlines the link inidcating
   its clickable but if i hold option and hover that underline doesn't happen, can we show underline even when you
   hold option, so we have cmd+click, option+click, let's make sure this is consistent acroos our app"
4. "and if certain file is html  in terminal, that should be opened in browser by default, even in file explorer by
   default it should be opened in file editor but within the editor there should be an option like open in browser,
   like add an icon which opens that html in browser. this is only for html, and if any html links is hovered in
   terminal that should open in browser by default"
14. "oh wait looks like opening in browser for html works fine, jsut make sure whatever i mentioend all works fine with
    cmd+click option click etc"
   - ⌥ held over a link shows the same underline and pointer as ⌘, in the terminal and in every card with links.
   - File Explorer opens an `.html` in the file editor, whose header gets an Open in Browser button.
   - A check of ⌘-click and ⌥-click on HTML and other links in the terminal, Markdown, Git, chat and the browser.

## Track D: cards that survive a long idle (items 9, 17)

9. "sometimes browser panes becomes blank if i leave them idle for long and refresh or anything doesn't fix it i have
   to close the browser pane and open fresh one to fix it, is this more like that browser process ended or something
   where we have a limit right and those don't recover may be on active? figure out what causes the browser panes to
   go blank and provide proper fix"
17. "similar issue like browser pane getting blank, i see markdown pane left idle for long, it shows raw markdown in
    rich text view weirdlt have to refresh the markdown pane to fix it, may be this is also becasue something getting
    killed in background or something?"
   - Find the cause first (a WebContent process ended by the system or by the kept-card limit, a lost bridge); prove
     it by forcing it. Fix the cause so the card comes back by itself with its state, and Reload always works.

## Track E: keys and padding (items 5, 13, 15, 16)

5. "one weird thing noticed in markdown with read only mode, when i do cmd+a it doesn't select the markdown text in
   source mode, in normal rich text mode cmd+a works fine, but as soon as i swtich to remove read lock then the cmd+a
   works, lets' fix this"
13. "instead of ctrl command arrows for back and forward in file explorer, can we use some other shrotcut, that ctrl
    command arrows conflict with other app shorctus i have. make sure it doesn't collide with any of our own app
    shorctus and general common shorcuts of other apps"
15. "that git diff cmd + [ ] hotkeys can we also have cmd+shift+[ ] for file jumping"
16. "i think for all file explorer, git and browser in floating pane can we have some slight top padding, right now its
    too close to border i feel, no changes in normal panes, only in floating panes"
   - ⌘A selects all in a locked Source view.
   - Back and Forward move to a pair checked against Ovvi's keys, macOS and common apps (VS Code's ⌃- / ⌃⇧- is the
     first candidate).
   - Note: in Git's diff `]` `[` jump by change; ⌘⇧] ⌘⇧[ jump by file, unless they clash with Ovvi's own keys.
   - Floating windows only: a little top padding above a plugin or browser card's bar.

## Track F: the remote browser stays up (item 6)

6. "that issue where within devvm-aai where browser doesn't load the url, it still does happen occasionally? i have to
   close th connection and connect back to remote ssh again to fix it, is there a chance that ssh proxy forwarding
   thing breaks sometime? investigaet and fix any flakiness to this"
   - Find how the SOCKS forward dies (the ControlMaster, sleep, a dropped forward) and make it heal by itself.

## Track G: Relaunch with Chat (item 7)

7. "oh and relaunch with chat is failing now, it shows claude didn't quit or codex didn't quit errors? this didn't use
   to happen before, do we have a timeout or something added recently that's causing the issue, fix it either
   increase timeout or fix the underlying issue"

### Track G findings

- **No new timeout.** The quit wait (`HostStore.quit`, 10 s from its ⌃C) is unchanged since phase 40; no commit since
  October touches the quit path, `program`/`isShell` or the per-call `herdr remote-api-bridge`.
- **herdr is right.** Spiked with a real managed `claude` (2.1.312, isolated `CLAUDE_CONFIG_DIR`, herdr's session hook)
  and `codex` (isolated `CODEX_HOME`) in `ovvi-dev-p57g`: after the quit the shell is in front and `pane.get` has no
  agent, also with a reported session.
- **Cause: the 10 s ran out.** It held a fixed 2 s wait, each herdr call (one process each: about 1 s apiece at a load
  of 300, 0.1 s at a calm one) and the agent's own exit. A managed Claude Code is a launcher with the native binary
  as its child; on `/exit` the launcher's preset plugins run their SessionEnd hooks (`meta-trajectory` has an 8 s
  timeout) and the launcher ends after its child. The dev app with a trace saw the shell 9.4 s into the 10 for a
  two-line session at load 300 (4.3 s before the quit command went in, then 5 s for the exit): a real session ran
  over and got "did not quit".
- **Codex** exits on ⌃C: the dev app relaunched it in 2.3 s at load 107. Its "did not quit" was not seen here; with
  the user's own config (hooks, MCP servers) and a starved Mac its exit and the calls take longer, which the same
  budget covers.
- **Fix:** 30 s. A real agent's exit is bounded by its hooks' timeouts, so this is a bound, not a moved break. The
  `ovvi chat` advice goes from `--timeout 20` to 40.
- A relaunch types the agent's line into the shell: a `CLAUDE_CONFIG_DIR=… claude` typed by hand is not kept, so a
  by-hand spike exports the isolated config in the pane's shell first.
- **Runs:** the slow-exit test on the old 10 s, run 42443296822: red (`testEnableChatStartsAnAgentAgainInItsSession`,
  the composer never came). With 30 s, run 42443299852: green, executed 1 test (38.7 s). `make lint build test` and
  the docs build green on the rebased tree.
- Not done: the polls while the shell is back but herdr still reports the agent sleep 2 s, not 0.3 s (fine for
  correctness).

### Track G findings, round 7 (item 82)

- **herdr's detection, not Ovvi's: left as is.** In `ovvi-dev-p57g` a stand-in `claude` script (prints "Current
  version…", "Checking for updates…", sleeps) run as `claude update`: herdr's `pane.get` gave `agent: claude` at once
  (`agent_status: unknown`), then `idle` 2 s later, for the whole run. `pane.process_info`: `/bin/sh
  /tmp/…/claude update` and its `sleep`. `herdr agent explain`: `agent: claude`, `state: idle`, manifest
  `remote:…/agent-detection/remote/claude.toml 2026.10.11.1`, `rule: none`, `fallback_reason:
  default_known_agent_idle_fallback`. A real `claude update` is a process named `claude`, which herdr takes the same
  way.
- **How herdr decides** (herdr.dev `agents.mdx`, 0.9.5): it finds a known agent's process in the pane's foreground
  (by its process, whatever the arguments), then reads the live bottom of the screen against that agent's detection
  manifest for `idle`, `working` or `blocked`; with no rule matched, a known agent counts as `idle`
  (`default_known_agent_idle_fallback`). An integration's own reports replace the screen reading. `HERDR_AGENT=` on a
  wrapper names an agent herdr cannot see; there is no way to say "not an agent".
- **Ovvi** takes `pane.agent` and the status only from herdr's snapshot (`HostStore` sets `pane.agent = new.agent`);
  its sidebar rows and progress come from them. Its own launches (`Launch`) only mark chats Ovvi typed. Nothing to
  change in Ovvi; a fix belongs in herdr (a subcommand list per agent, or no agent until a manifest rule matches).

### Track G findings, round 7 (item 87)

- **Cause.** The floating window's title row drew its own copy of the card's agent control, with only the Chat | TUI
  switch, so an agent with no chat showed nothing there.
- **Fix.** One `AgentControl` (the switch, else Relaunch with Chat) in both the card's agent row and the float's title
  row, gated the same way (no plugin pane). The float already shows the chooser's loader and the chat, so the
  relaunch's loader and its chat land in the float.
- **Not fixed.** A failed relaunch's notice shows on the main window's tab page, as every notice of the session (the
  design's Notice); a float shows no notices. Moving notices into floats is a design change for every notice.
- **Runs.** Red on the old code with the new test: CI 42949337434, and locally dark and light (no button in the float).
  Green locally dark and light. Pictures: `~/Downloads/ovvi-research/p57g/r7/`.
- **For the user.** Float an agent started by hand (`claude` in a terminal): Relaunch with Chat sits left of the pin;
  click it, the float shows "Starting…" and then the chat with Chat | TUI.

### Track G findings, round 5 (item 44)

- **Spiked on plain installs** (npm into `/tmp`, an isolated `ZDOTDIR` shell with each agent's store in `/tmp`, in
  `ovvi-dev-p57g`): npm's pi sets `process.title`, and on macOS libuv writes the title over the argv area. herdr's
  `pane.process_info` then lists `name: node, argv0: pi` and no argv (`node -e 'process.title="pi"'` and `ps -o args`
  show the same). Ovvi found a chat only by the marker in the argv, so the card stayed a TUI with Relaunch with Chat.
  Claude Code before its native build did the same. npm's Claude Code 2.1.319 is now native (`claude.exe`, argv kept),
  Codex's npm wrapper has a native child with the argv, OpenCode is native with the argv. Managed launchers keep the
  flags in a parent process, which hid it here. herdr's own pi integration works around it too (it reads the parent's
  args). Track P's report (CH-1) came to the same cause.
- **Fix:** the store keeps the launch Ovvi typed, by terminal (`Launch`), bound to the agent's processes the first
  time herdr lists one named as the command (`claude.exe`, an `argv[0]` title), only from answers newer than the line.
  While those run, the pane is that chat; a hand-started agent, the bare-command fallback and a start that ended
  without its agent get none. The loader asks again for 10 s while neither marker nor launch shows. A relaunch that
  ends without the chat says why for 10 s with **Retry** (did not quit, did not start again, started again without
  chat, not back after 10 s), and no longer leaves the pane opening on its chat later.
- **Tests:** stand-ins drop their arguments with `OVVI_STAND_IN_TITLE=1`, and Claude's refuses its first flagged
  resume with `OVVI_STAND_IN_FAIL_RESUME`. `testRelaunchSaysWhyAndRetriesWithoutArguments` (notice, Retry, chat with
  no argv) is new; `testAPiRunListsEveryKindOfTool` runs pi with no argv.
- **Runs:** old detection with the new stand-ins and tests, run 42565388115: red, both new checks. The fix at
  87825163, run 42565499077: green, executed 8 tests (one skipped by design, needs a real claude), covering the
  launcher path's tests too. `make lint build test` green on the rebased tree.
- **By hand** (the dev app on `ovvi-dev-p57g`, real npm agents): Relaunch with Chat of npm Claude Code opens its chat
  before and after (native, argv kept); `ovvi agent pi` with npm pi had `chat: false` before and `chat: true` after.
- **Follow-up: the chat outlives the app.** A bound launch with no marker in sight goes to herdr as the pane token
  `ovvi-chat` (command, marker, pids; no `ttl_ms`), read back at the first sight of a terminal. Spiked: such a token
  merges per key with `ovvi`'s timed ones and stays while herdr's server runs; a server restart gives the pane a new
  terminal id and no token. The pids must still run in that terminal; their start time is not checked (ponytail note).
  `testAPiRunListsEveryKindOfTool` now relaunches the app and opens the restored chat. Old launch, run 42567656627:
  red at the relaunch check. The fix at ea2bfcc1, run 42567956216: executed 4 tests, 0 failures (its artifact upload
  then hit a network error; two earlier tries died downloading herdr and libghostty).
- **Regression fixed: the loader waited for the tie.** `settle` ran inside the chooser's wait, so an agent whose
  processes are never named as its command (a shell function, a wrapper; `testPickingAnAgentStartsItBehindTheLoader`'s
  `sleep`) held New Pane's loader up to 10 s (p57r's run 42575992688). The loader goes again after one ask; the tie is
  looked for behind it, and a relaunch's notice waits for it. Run 42577364363 at 92e81ace: executed 5 tests (that one,
  the pi relaunch-of-the-app test and the three relaunch tests), 0 failures.

## Track H: redraw a terminal's TUI (item 8)

8. "one more feature i wanted, is to have a shortcut to refresh tui, what i mean is sometimes agent inputs will become
   like this: <screenshot 5.18.41> if they are left idle or after sleep etc. and fix to this is to resize the window by
   either adding a new pane etc so the tui rerenders and those errors goes away, similar to cmd+shift+r which replaces
   the pane, we should have some way to rerender the tui, this should apply only for terminal panes not for others,
   figure out what shorcut would fit well, and see if we can do this rerender with that shortcut easily, should be
   there in cmd+k as well"
   - Also find what writes the `kq_dispatch` lines into the pane.

### Track H findings

- **Who writes `kq_dispatch`.** The managed launcher binaries, not herdr (clean), libghostty or the agents' own code:
  `/usr/local/bin/pi_cli/pi`, `codex_cli/codex`, `claude_code/claude` (and `launcher_sensitive`, `fast_mux`, `meta`,
  `x2pagentd`, about 80 binaries) link xplat's `libevent-1.4.14b-stable` with a patched `kqueue.c` that warns
  `%s: skipping fd=%lu errno=%lu` when kqueue reports EBADF (9) for an fd that was closed while watched (after sleep).
  `event_warn` adds `strerror(errno)` of a stale errno, hence "errno=9: Operation now in progress". The launcher
  stays the agent's parent and its stderr is the pane's tty, so the lines land on the TUI's screen. Neither Ovvi nor
  herdr can stop it: they are the program's own output. The fix is the launcher's (its oncall:
  devinfra_3p_ai); a stopgap on the user's side is `EVENT_NOKQUEUE=1` in the environment (the launchers' libevent
  then uses poll; not tried for side effects, Ovvi does not set it).
- **Redraw Terminal (⌥⌘R).** herdr has no redraw call. Over the control stream the PTY goes one column narrower, then
  back to the card's grid once the program drew at the narrow width (frames quiet 150 ms, from 250 ms, at most 1 s):
  two SIGWINCHes, and a TUI repaints all at a new width. A width change only once both landed would be no change
  to a Node TUI (it compares sizes), hence the wait. The card keeps its old picture until the frames at its grid
  settle. Spiked on herdr with pi, Claude Code and Codex (stray lines gone after; still there without the nudge);
  zsh redraws only its prompt. ⌥⌘R is Terminal's Soft Reset and free in Ovvi on terminal cards; on plugin cards it
  stays Reload Plugin (the two never meet). ⌃L stays the program's.
- **Runs.** CI chosen tests: 42440812804 (the test waited for text `clear` had wiped), 42441450383 (a long prompt
  wrapped the trap's line; the palette listed the test's tab "redraw" first; the redraw itself and PackageTests'
  ⌥⌘R and Replace Pane's palette test passed), 42442000714 green: testRedrawTerminalMakesTheProgramRepaint.

## Track I: chat times and ticks (item 10)

10. "one more improvement to chat view, to have timestamps and single tick and double ticks: <screenshot 6.01.48>,
    similar to this. basically show single tick when message is sent, and double tick when its processed by agent, i
    think right now as well we show that by slightly dimmed color when the message is not yet processed or something
    right, we change that to show like single tick and double tick, and show timestamp for each message, let's show
    timestamp for assistant messages as well. no ticks needed for assistant messages"

## Settings icons (item 11)

- "and the image for different settings variations is lost as it was in /tmp folder and i restarted macbook, can you
  show that image again". The options are drawn again into `~/Downloads/ovvi-research/`; the pick lands in this phase.
- Item 25, "for settings, let's try out option b, and also can we add some padding between search and first menu
  option, only slight increase": option b of `~/Downloads/ovvi-research/settings-icons/options.png`.

### Findings (Settings icons)

- **Fix.** `SettingsIcon` draws option b: a 22 pt tile with 6 pt corners, lit from the top (dark: #505056 to
  #36363B with a light rim; light: white to #ECECF0 with a fine dark rim), and a filled two-tone (hierarchical)
  symbol at 13 pt medium, #ECECEC in dark and #48484E in light. It stays one layer, so a selected row does not tint
  it. The first row sits 6 pt lower under the search field (`safeAreaPadding`): the list's `contentMargins` moved
  nothing (the sidebar's table sits under the field).
- **Pictures.** Before and after, the sidebar and the pages, dark and light: `/tmp/ovvi-shots/p57s/` and
  `~/Downloads/ovvi-research/p57s/r2/`.

### Runs (Settings icons)

- `testSettingsPagesSearchAndLook` green locally before and after (it takes the pictures), and in chosen-tests run
  42528799814 on 1b1565e3.

## Findings

### Track A

- **Cause.** Each state drew its own look: `ContentUnavailableView` in the window, hand-made stacks of 28–44 pt symbols
  in the cards, a caption and a button at a terminal card's foot, three spinners (`Waiting`, `Loading`,
  `PluginLoader`). A missing herdr showed only a command to copy. ⌘N opened the machine's `default` by itself.
- **Fix.** One `EmptyState` (symbol, title, one line, at most two buttons, a compact size for lists) and one `Loader`
  (icon, spinner and line, an optional line of progress) replace them in the window, the cards, the filter lists and
  the chat. Install herdr runs herdr.dev's `curl -fsSL https://herdr.dev/install.sh | sh` on This Mac or over the
  machine's SSH connection, shows its last line, its output on a failure, then forgets the cached herdr path, starts
  the session on This Mac and reads every page of the machine again. ⌘N opens `SessionPicker`: each machine's
  sessions on the Open Session panel's glass; a pick opens the first page.
- **Decisions.** The lookup also tries `$HOME/.local/bin/herdr`, where the installer puts it, since macOS's zsh and
  many remote shells lack that folder on `PATH`. "herdr is too old" gets no Update button: the running server's
  version counts, and only a restart that ends its programs changes it. The install has no Cancel: a kill reaches
  only its `sh`, not the pipe's `curl` (no process-group signals). A machine whose sessions
  cannot be read lists `default` with why; its page has the fix (Install, Connect). The first window still opens
  `default`; restored windows are kept. A `-session` run's picker lists only `ovvi-*` sessions. Settings' search keeps
  the system's `ContentUnavailableView.search`, as System Settings has it. The sidebar's and Archived Sessions'
  states are left to Track B, which reuses the two views.
- **Cause (found by the pictures).** A machine that failed its first connect showed a blank page, not Reconnecting:
  the overlay sat on a view that drew nothing. Its content is now a clear view.
- **Runs.** BEFORE pictures: an on-demand `testStateScenes` on a tag of main (run 42439654506), its W8 blank. AFTER pictures and the 24 chosen tests (picker, install on This Mac and over SSH, windows, remote, the restyled cards and pages) green on CI (runs 42442658071, 42443827701).
- **No picture.** A plugin's error card (it needs a broken plugin package), "No tabs in ‹workspace›" (herdr 0.9.5 closes a workspace with its last tab), "No layout for this
  tab" (no split tree herdr sends fails), "The terminal stopped" (a stream failure needs a herdr updated under a
  running server), and the loaders that show for under a second (a plugin opening, an agent starting, an overview
  tile, a chat's history): each is the one `EmptyState` or `Loader` the pictured states show.
- **For the user.** Click Install herdr on a Mac or host without herdr (and an offline Mac's error). ⌘N with
  remote machines in the list: it reads every machine at once under BatchMode, so a host that needs a password lists
  `default` "Not connected" and one that hangs shows its spinner row up to 30 s; Esc closes the window.
- **Round 2, cause (18).** A remote machine's read waits in `SSHExec.up` behind any start in flight; a Connect whose
  ssh question is still open never ends, so that machine's row spun for good. This Mac's row has no such path (a
  login-shell lookup of at most 3 s, then herdr's 10 s output limit), and old code with a slow This Mac and an
  unreachable host resolved both rows in a test, so This Mac's stuck row is not reproduced.
- **Round 2, fix.** Each machine reads in its own task, and a row still unread after 15 s says "No answer within 15 s"
  (a structured timeout would hang too: the wait on the other start ignores cancellation). A remote machine's failure
  rows and the Disconnected page use `network.slash` (23); a missing herdr keeps the box.
- **Round 2, runs.** testNewWindowRowsResolveWhileAnotherConnectAsks (Password Host's Connect left asking, then ⌘N):
  red on the old code at its 20 s wait for the row to go (run 42527933646), green on the fix with the scenes, the
  picker's and Password Host's tests (run 42527936883).
- **Round 4 (31), decisions.** Ovvi opens a session only when asked: `-session` (tests), a restored window, or a
  window opened for a machine (the machine menu, Add Remote Host). Anything else (a launch with nothing to restore,
  ⌘N, a Dock reopen) shows the new-window view. Of three drawn variants (one list, a card per machine, machines left
  and sessions right; `~/Downloads/ovvi-research/p57a/r4/variants.png`) the one list won: one field and one keyboard
  path (type, arrows, Return) over every machine, the Open Session panel's look, and it grows down with more machines.
  Install herdr in the list opens the page and installs at once; Connect opens the page and asks there. Add Machine is
  the Add Remote Host dialog in the same window, Edit Machines opens Settings ▸ Machines. New windows fill the screen's
  visible frame.
- **Round 4, measured** (the dark picture, 2× pixels): the window is 3456 × 2168 px (1728 × 1084 pt, the visible
  frame); the icon's artwork is 126 px wide in its 160 px (80 pt) frame; "Ovvi"'s cap top 703 px; the panel spans x
  1288–2171 (884 px: 440 pt plus its 1 pt edges), y 795–1555; the field starts 17 px under the panel's top edge, and the
  last row (Edit Machines) ends 21 px over its bottom edge.
- **Round 4, cause found on the way.** `-machines []` never reached the argument domain (it drops a value it cannot
  read as a property list), so the machine list's isolation guard saw only `-session`: a test launched without it read
  the user's machine list, and the new-window view tried their SSH under BatchMode once (it failed). The guard reads
  the raw arguments now.
- **Round 4, review.** Typed text puts the machines with a matching session first, so Return opens a match, not a new
  This Mac session; the fix rows and spinner rows hide unless the machine's name matches; New Session picks a free
  name as it starts, and a throwaway run offers it only for typed `ovvi-` names; Add Machine opens the machine in the
  same window when it has no page; a notification click or a float URL that starts the app opens its session in the
  first window, not the view; `-defaultSession` isolates the machine list too. The view on screen takes such an ask at once. The app's
  Appearance setting was applied only by a window with a page, so a view alone (a cold launch) followed the Mac's
  appearance: it is applied at the scene now.
- **Round 4, runs.** CI 42559510070 (12 tests), 42561224398 (14) and 42562294731 (12, with both scenes) green.
- **For the user (round 4).** Quit with no window and launch, ⌘N, close every window and click the Dock icon: each shows
  the view, connects to nothing, and fills the screen. Type part of a session's name and press Return; type a new name
  and press Return (New Session); Add Machine…; Edit Machines….
- **Round 5 (49).** "herdr is not installed" (This Mac and remote) says why in one line, "Ovvi runs on herdr, which
  keeps your sessions running." (332 pt, as wide as the 326 pt command under it), over the install command, now a
  quieter tertiary line under it. Measured on CI's 1× pictures: the line is 332 px, the install command under it 324
  px (remote), 310 px for the tests' fake command on This Mac; the old 451 pt sentence wrapped at 420 pt into one long
  and one short line. Run 42580014495 green (scenes, both install tests).

- **Round 6 (54), cause.** The view opened with nothing known: every machine's first frames showed a spinner row,
  which the answer replaced a split second later. **Fix:** each machine's sessions as last listed (`KnownSessions`:
  memory, every page's own session read, and `sessions.json` under the app's own caches, by SSH target; memory only in
  an isolated run) show from the first frame, and the read behind them changes the rows in place. A machine with none
  known keeps one empty, unlit row's room and shows the spinner only after 150 ms; a remote that needs a password
  again drops its known rows. No fade: it would only mask the change. The local read was one herdr call already (the
  path is cached after launch). Measured in CI's screen recording (about 16 frames a second) before: the spinner
  rows showed for 3 frames (about 180 ms) after the window's first empty frame, then the column jumped 53 px (in the
  960 px wide frames of the 1024 pt screen) as the rows came; after: This Mac's rows in the first frame with content,
  and the column stays put to the pixel over the next 9 frames. Runs: 42590576288 (the new test, red on the old code
  at "the spinner row came first"), 42594833784 (9 tests and the scenes, green).
- **Round 6 (59), Add.** Settings' Add closes Settings, so the new machine's window, where ssh asks, is in front.
- **Round 6 (59), decision.** Settings ▸ Machines is the one place that adds and edits machines: the view's Add
  Machine and the machine menu's "Add Machine…" open its add form, "Edit Machines…" its list; the Add Remote Host
  overlay is gone.

- **Round 7 (63), cause.** Not the code: every app with the installed bundle id shares its saved windows, and a Release
  build an agent ran against a throwaway session (`-session`, a measure) quit last, so the user's next launch
  restored that window (`ovvi-dev-p57t` here), whose session is gone, and showed the new-window view. The restore code
  brings back two windows with their sessions (a new test). **Fix:** only `make install` and `make dmg` build the
  installed bundle id; `make app` (a measure) builds `dev.ovvi.app.release` (`ovvi-release://`), and Debug builds
  have theirs. Also a code cause: a quit with no window open saved none, and the next launch opened no window at all;
  now launch opens one new-window view then. Rules kept: a restored
  window opens its saved pages; a remote one whose machine needs an answer shows Disconnected with Connect, never a
  prompt; only a launch with nothing saved shows the new-window view; ⌘N always does.
- **Round 7 (64).** The sidebar's "No Spaces" and its New Space button are gone; the page stays quiet (the header's `+`
  makes a space). The window's content: Ovvi's icon, "This session has no spaces", one line, New Space and Open
  Folder…, then up to six Git projects of the session's machine (one shell run on This Mac or over SSH), newest change
  first. Measured on CI's 1× picture: the icon's artwork y 285–336, the title 194 px wide at y 358–372,
  the line 355 px at y 381–393, the two buttons 246 px wide, 28 px tall at y 410–437; before, only a 29 px dashed
  square, a 154 px title and a 133 px button. Runs: 42706306015, 42708486361 (found the no-window launch),
  42710210104 and 42711244306 green.
- **Round 7 (69), cause.** Until its restore or the new-window view decided (a launch reads herdr first, about 0.7 s
  here), a window's content was empty: no glass background and AppKit's plain title bar, then Ovvi's look. Measured
  in a local XCUITest recording (17.3 frames a second, 58 ms each): before, the window's middle went from the
  desktop's 22 to a plain gray 30 for 12 frames (about 690 ms), then to the glass 23; after, 22 straight to 23, the
  glass and title row from the window's first frame. **Fix:** that empty phase is `WindowStart`: the window's
  background and title row, and at launch (every restored window, or the first new one) Ovvi's icon (96 pt) in the
  middle until a window of the launch has its content; the content then fades in over 0.2 s. Later windows and ⌘N
  show the background alone. A window reader that comes during a full-screen change now hears its did notifications
  too. Runs: 42714517118, 42726405079 green (window, restore,
  traffic-light and look tests).
- **Round 7 (71).** The empty session's "Git projects" list and its shell run are gone; it keeps the icon, the title
  and line, New Space and Open Folder…. Measured on this Mac's 2× pictures: the column now sits 212 px lower, in the
  middle (the 7 rows are gone); the title is 386 px wide at y 1125–1154, the line 709 px at y 1171–1195, the buttons
  505 × 56 px at y 1229–1284.
- **For the user (round 7).** Quit with two windows open and launch: both come back with their sessions; close every
  window, quit, launch: one new-window view. A session you stopped (a reboot) is still skipped, so a window of only
  stopped sessions shows the view. An empty session: New Space and Open Folder….

### Track B

- **Built** (D111): one sidebar. Pinned tabs on top (a tab's hover pin before its ×, Pin Tab / Unpin Tab in its menu,
  the pinned row's hover Unpin; kept by herdr's tab id in `tabPins`, following a tab moved to another workspace), the
  workspace rows 6 pt apart, each with a chevron that unfolds its agents (one 28 pt line: tile, title, state box with
  the working time; newest change first, held still under the pointer), the selected row's glass over its agents, a
  border for an unfolded row not selected; Archived Sessions sticky at the foot. Track A's `EmptyState`/`Loader` for
  "No Workspaces", "No matching workspaces" and Archived Sessions' states. Gone: the Agents view and its button, ⌘.,
  View ▸ Show Agents, the ⌥ + swipe through agent rows, Settled and its setting, agent pins and pinned closed
  sessions, the page dots. Migration: `agentPins`, the Settled and old Archived folds and (outside a test's config
  folder) `settleAfter` are removed at launch.
- **First prompt.** An untitled session's name is its first typed prompt, cut at 100 characters with "…", read by
  the same title script only while there is no title (Claude Code's transcript, pi's file, Codex's `preview`); the
  hover card shows the whole name. UI tests point it at the fixture home (`-archivedHome`).
- **Finding.** herdr 0.9.5 ignores an `agent_session_path` (pi) reported from outside pi's own integration, also
  with the `herdr:pi` source; a `herdr:claude` session id is taken. The e2e test uses a Claude Code transcript in
  the fixture home.
- **Tests.** The session dots' clicks became ⌥⌘1–9 (`showPage`) and their checks `pageList()` (a `sidebar.sessions`
  test value). New `SidebarAgentsTests`; the Agents view's tests and the Agents panel's are gone or moved to the
  unfolded rows.
- **Runs.** Chosen tests on CI: run 42530659327, 45 of 46 green (every test the change touches but the stress test);
  `testPanelsAndSwitchesReactAtOnce` now counts the ⌥⌘1 that shows page one, and run 42532170243 ran it with
  `testHundredsOfPanesStayQuick`, both green. Pictures, before (main 3e817298) and after, dark and light, every mockup state:
  `~/Downloads/ovvi-research/p57b/r2/index.html`.
- **For the user.** Pin a tab and drag it to another workspace; unfold several workspaces and watch an agent change
  under the pointer (it moves 1 s after the pointer leaves); an untitled Claude Code, Codex or pi session's first
  prompt in its row and hover card; Archived Sessions open while the workspaces scroll.

### Track C

- **Cause.** libghostty underlines a link and reports it (the pointing hand) only while ⌘ or ⌃ is down, and its
  link rules are not in its config. The app now gives libghostty ⌘ in place of ⌥ alone: with plain pointer moves,
  and on any modifier change with the pointer still over the terminal and no button down (off the view first, since
  libghostty looks again only on a new cell). Drags keep their own modifiers, so ⌥-drag still makes a rectangle.
- **Fix.** Every other card already looked the same with ⌘, ⌥ or neither. Unlocked Markdown drew no hover on its
  live links: links off the caret's line now underline and show the pointing hand, as locked.
- **Decisions.** A link to an HTML file on This Mac opens its page in a browser pane everywhere a link is (the
  terminal, Markdown, with the link's query and fragment); File Explorer's tree and Git diffs open HTML as text, and
  a file card on HTML has Open in Browser (`globe`, before Open With), which opens the page in a new tab, selected.
  On a remote machine HTML opens as a file. Copy Link on such a link still copies the path.
- **Decisions.** The terminal's accessibility title is the link under the pointer while ⌘ or ⌥ is down: VoiceOver
  reads it, and the UI test checks ⌥ through it.
- **Runs.** testCommandClickOnALinkOpensIt (⌥ pressed over a link, moved to another, released) and the new
  testHtmlOpensInTheBrowserFromLinksAndTheFileCard (⌘- and ⌥-click on a Markdown link to HTML, the button, no
  button on a `.txt`) green locally.
- **For the user.** Hold ⌥ over a terminal link with the pointer still, then move it: the underline and the
  pointing hand show as with ⌘. A ⌥-drag still selects a rectangle. Open an `.html` from File Explorer: it shows as
  text with the globe button.

### Track I

- **Cause:** every adapter already read each entry's time from the agent's transcript; the rows dropped it, and a
  message on its way showed only as a dimmed bubble.
- **Fix:** user and reply rows carry their entry's time. Each bubble shows it under its text at the right; the user's
  add one tick once `agent.prompt` took the message and two once the history has it. The dimming is gone.
- **Decisions:** a message from another day shows its date too ("Nov 5, 8:18 AM"). "Not sent" keeps its time and drops
  its tick. Two overlapping `checkmark` symbols make the double tick (SF Symbols has none). VoiceOver reads the time
  with "Sent" or "Delivered".
- **Runs:** the long-chat tests failed on CI once the row ids sat on the text, not the bubble: the run's width check
  measured from the bubble, and a reply whose text sat just above the top left the "rows at the top" set while its stamp
  still showed. Both checks now measure the text; the ten chat tests ran green on CI.
- **For the user:** reopen an old Claude Code, Codex, pi or OpenCode chat and check the times match the agent's; send
  while pi works and see one tick turn into two when it takes the message.
- **Round 2 (item 24):** the time sits 6 pt under a bubble's text (was 2), code blocks included, and "Not sent" stands
  alone: its Show TUI button is gone (the header's switch shows the TUI). The red "cannot read this session" card keeps
  its Show TUI, the only way out of that error in the chat.
- **Round 7 (item 77):** the times and ticks are gone, with their data (the rows' times, the message's sent flag) and
  their tests; the transcripts' times stay on the entries, for Worked. Bubbles take Messages' padding, measured on the
  user's 2x shot: 12 pt beside the text and 7 pt above and under it (was 18 and 16), radius 18 kept (no tail). A
  message on its way draws as a sent one; "Not sent" stays a small red line under it. The tool line keeps its 18 pt
  pull-out (its rows' text inset), 6 pt past a reply bubble's edge.
- **Round 7 (item 80):** the padding already matched iMessage (text 20 px from a bubble's top, 24-26 px from its sides
  at 2x); the rhythm inside did not. iMessage sets 13 pt text 16 pt apart (1.23x), a blank line between paragraphs and
  list items as plain lines; ours had 14 pt text 21 pt apart, 12 pt between blocks and 6 pt between items, so
  paragraphs ran together. Now: 17.2 pt lines (1.23x, iMessage's 13-on-16), 17 pt (a line) between blocks, list items
  as lines, 26 or 17 pt above headings, corner radius 15 (iMessage's corners fit about 15 pt; ours at 18 fit 17.5).
  Kept: 14 pt text, the column's width and the turn's rows between bubbles. A 440 pt cap (iMessage's measure) went in
  and came out again: the user found the messages too narrow. The shared `Capped` layout keeps its fix from then: it
  places its view with the offer it measured with, as its own height stretched a table's flexible cells. Pictures: ~/Downloads/ovvi-research/p57i/
  r7b (rhythm), r7c (the cap), r7d (the full width back, with a code block and a table).
- **Round 7 bug (stale chat on show):** Chat picked after a turn ended in the TUI showed the old rows for about 0.43 s,
  then the new ones and a scroll jump. Cause: the adapter follows only while a view shows the chat; a view shown again
  drew the old history while the follow read the new lines from the marks off screen. Fix: a chat that nothing followed
  is not current; when Chat is picked (or the view is made again: floated, detached, another session), the card keeps
  its TUI while the chat catches up (2 s at most), then shows it current, at the bottom. A follow per hidden chat was
  the other way: a process each.

### Track E

- **Cause, item 5.** A locked view's keyboard is on its scroller, so ⌘A is WebKit's Select All of the whole page. It
  starts at the page's first selectable text (Source's line numbers, Rich Text's open outline) and ends past the
  editor (Source's divider button, its shown page). CodeMirror takes a page selection only when both ends are in its
  text, so its selection stayed, or collapsed, and nothing drew. Shown with an offscreen web view; making the line
  numbers unselectable was not enough (CI: the divider still ended it outside).
- **Fix, item 5.** The Markdown page takes Select All's `selectstart` on the body while locked and selects the file
  in CodeMirror, as unlocked.
- **Decisions, item 13.** Back and Forward are ⌃- and ⌃⇧- (VS Code's and Sublime Text's Go Back and Go Forward). No
  Ovvi key (⌘- is the text size), no macOS key binding, no CodeMirror default, and no common launcher, browser or
  Xcode key uses them. A terminal reads ⌃- as undo, but the keys act only over a plugin card. ⌘← ⌘→ stay outside
  text fields.
- **Decisions, item 15.** Every ⌘ pair of `[` `]` is Ovvi's: ⌘ panes, ⇧⌘ tabs, ⌃⌘ workspaces, ⌥⌘ sessions. So a
  diff steps by file on } and { (⇧] ⇧[), the shifted pair of ] [ (by change), which is what the user's "cmd + [ ]"
  means. A step into a folded (Viewed) file unfolds it, as a pick in the file list does.
- **Decisions, item 16.** 6 pt above a floated browser's toolbar and a plugin's row 2; pane cards unchanged (4 pt
  since item 21).
- **Decisions, item 21.** 4 pt above the row: its 22 pt buttons, centered in 36 pt, then sit 11 pt from the card's top
  edge, as from its left. The tests compare Back's two insets.
- **Decisions, item 26.** Markdown's lock is a pencil, gray while locked ("Edit") and in the accent while editing
  ("Stop Editing"), the macOS idiom of one glyph lit while a mode is on. Options drawn side by side first: the lock,
  pencil.slash / pencil (the slash is hard to read at 11 pt), eye / pencil (two glyphs for one switch), square.and.pencil
  (reads as New Note), eyeglasses / pencil.line. Lock Editing (⌘E) keeps its lock: its checkmark means locked.
- **Runs, round 2.** Chosen tests 42527697268 green (3 tests: Markdown, the header's floating row, the floated
  browser).
- **Runs.** Chosen tests 42440766856 red on the first fix (line numbers only: Source's divider still ended Select All
  outside the editor; the diff lost the keyboard to row 2's button), 42442867391 green (6 tests). The floating header
  check in testAPluginsHeaderDrawsItsManifestsControls is not reached on CI: that test fails before it on main since
  phase 56 (its filter field 55 pt wide); the row's 6 pt checked locally.
- **For the user.** In a Git diff, ⇧] and ⇧[ jump by file (not ⇧⌘] ⇧⌘[, which switch tabs). Try ⌃- and ⌃⇧- in File
  Explorer and Git against your other apps. ⌘A in a locked Source view selects the source, also with its preview
  shown; ⌘C copies it.
- **Decisions, item 38.** The ⌘ and ⌃⌘ keycap hints on tabs and spaces are gone with their monitor and tests; the
  palette keeps its keycaps.
- **Cause, item 40.** In a floating window Back has 11 pt above it, but under it the row's own 7 pt plus each page's
  top padding: the browser's page 0 (7 pt), the tree 6 (13), a Git diff 8 (15), the Git home 10 (17); CodeMirror's 4
  (11) was right. At 2x from the card's border: 22 px above Back, under it 14, 26, 30, 34 and 22 px.
- **Fix, item 40.** Every plugin page starts its content 4 pt down (CodeMirror's; the Git home's as a border of its
  scroller, so it stays while the home scrolls; a commit's subject too), and the floated browser's row has 4 pt under
  it: 22 px under Back on every card, and 18 px above and under the path and address fields. Rich
  Text keeps its 28 pt page margin. In a pane the same pages then started 9 pt under Back (they had 11 to 17; 11 since
  item 53); Back
  has 5 pt above it there, under row 1.
- **Fix, item 40, chat.** A bubble had 8 pt above its text and under its time: 23 and 22 px to the letters at 2x, 38
  px at the sides. 16 pt now: 39, 38, 38 and 38 px.
- **Runs, round 4.** Chosen tests 42557814388: 5 of 6 green, the floated browser's page gap read 11 vs 12 pt on CI's
  1x screen (the card's frame rounds; now 1 pt of slack); 42559159986 green (5 tests: browser, Git card and home, File
  Explorer's floated `..` row, floating chat).
- **For the user, round 4.** Panes changed too: plugin pages started 9 pt under row 2's Back there (were 11 to 17
  pt, different per plugin; 11 since item 53). Markdown's Rich Text keeps its 28 pt page margin. Chat bubbles are taller (16 pt above the
  text and under the time).
- **Fix, item 53.** A pane's browser and plugin cards keep row 2 where it was (Back 5 pt under row 1) and leave
  2 pt more under it, 6 pt under the browser's toolbar (`headerHeight`): Back has 11 pt under it to the content, as
  in a floating window. At 2x from Back's bottom edge, before and after: the browser's page 10 and 22 px; the tree's
  first row, a Git diff's box, the Git home's Message field and its scrolled history, a file's first line 18 and
  22 px; a commit's subject line 18 and 22 px (its letters 26 and 30). Agent cards are unchanged.
- **Runs, round 6.** Chosen tests 42590765920 green (6 tests: both File Explorer tests, the browser, Git, Markdown,
  the plugin header).

### Track F

- **How it was looked at.** The user's devvm-aai master, read only: one per-app socket (phase 56's fix is in the
  running app), master alive, no `-D` (no remote card open). WebKit's unified log holds only hours, so no failure was
  caught live. Each way the forward can die was played against a throwaway sshd on 127.0.0.1 with the app's exact
  ssh argv.
- **Likely cause: the front could kill itself.** Its listener's start handler stayed on for its life: a later
  `.waiting` (Network's "waiting for a network") or `.failed` cancelled it for good, and the store kept the dead port.
  That matches "browser only, until the window closes": only the last card's close makes a new front. Not seen live:
  this Mac's network cannot be turned off under the other agents, and WebKit's log keeps only hours. The proxy now
  logs (`dev.ovvi.app`, category `proxy`, error level, kept for days) when its listener ends, listens again, or
  forwards again, so the next report names the path.
- **Smaller causes.** A card whose proxy did not start (its listener waited at start) said so until the window
  closed: Reload never asked again. A forward made on a master whose pid a new process has (pids went 68431 to 98041
  in two minutes on this Mac) failed every page until a herdr run noticed; with a session's window open that came
  soon, so it was short.
- **Not causes.** A master that dies (SIGKILL, a dead link after 15 s of ServerAlive, sleep) is started again on the
  next page, which forwards again. A page in the first 15 s after a dead link waits, then fails once. WebKit applies a
  changed proxy to existing web views and keeps it across a crash of its network process. A refused proxy never falls
  back to a direct load.
- **Fix.** A `-D` port that nothing answers on gets one new forward and one more try. A forward that fails checks the
  master with `ssh -O check` and starts a new one if it is gone. A front whose listener ends listens again on its port
  every 2 s until it can. Reload starts a proxy that did not start.
- **Decisions.** No retry when ssh accepted and the machine refused: that is a real answer. Only a port that takes
  no TCP connection counts as a lost forward: ssh's `-D` holds even its greeting reply until the machine opened the
  connection, and closes without it when it cannot (a local run with real ssh and WebKit caught the first version
  reading that as a lost forward). No wake or
  network observer: the next page does the check. No time limit on ssh's greeting: a stopped master (SIGSTOP) still
  holds a page for WebKit's 60 s. A master that does not answer `-O forward` in 5 s is left behind for a new one, as
  the relay does. The user's symptom (an error or a spinner) is worth asking.
- **Runs.** The remote browser test now cancels the master's `-D` and kills the master, and loads a page after each.
  Red: 42442213887 and 42442741517 (its text check missed CI's `sshd-session`; the who server's log showed the healed
  page came). Green: 42443261958 (2 tests).
- **A lost click (after the push).** A full run failed the remote relay test: it clicked a card still loading, and
  the window gave herdr's focused pane the keyboard. The click had hit the card's spinner, which took it: the loader
  overlay now lets clicks through to the terminal. A new test clicks a card whose stream waits on a stopped server;
  it failed on the old code here, and the remote tests now also wait for the card to draw before they click.
- **A page that never came (a later full run).** Not the proxy: the page after the dropped master was never asked
  for (the who server got no request). The drop shows Reconnecting over the page for 0.8 s, which takes no clicks;
  the test's click on the address field fell in it, and the typed address went to the page. The test now clicks
  until the field has the keyboard. A stopped master still holds a page until WebKit's 60 s, then it fails.
- **The endless spinner (the user's answer).** ssh's `-D` holds a page's greeting until the machine opened the
  connection, and nothing bounded that wait: with the master or its link hung, the page spun for ever. A stopped
  master never runs ServerAlive, and a master whose keepalives still pass can leave a channel open unanswered. Now
  the greeting gets 5 s; then a relay run (3 s) tells a hung master from a slow machine. A hung one gets `-O exit`
  (1 s) and a new master, and the page one more try; a slow machine gets 30 s more; then the error page. Measured
  here with a throwaway sshd: a stopped master's page came in 9.4 s, a stopped server side's in 9.7 s. devvm-aai's
  channel open was not measured: a new connection there asks keyboard-interactive, and the user's master is off
  limits. A test stops the master on CI. Pages that stall together share one check. Not covered: a connection
  WebKit already holds (a Reload of the same page) on a master that stays stopped waits WebKit's 60 s; a link that
  hangs ends it sooner (`-O exit`, or ServerAlive in 15 s). Runs: green 42546671665 and 42547529376 (2 tests each,
  the stopped master among them).
- **Item 83, overlapping Reconnecting (round 7).** Two owners drew a card's state: the page's Reconnecting overlay
  and each card's own ("The terminal stopped", read from its stream and its page's store). The user's build already
  had the card's `live` check and still drew both (the shot is from 12:39 PM, after it). Two ways in: a failed read
  keeps the store `.live` while it finds out why (up to ssh's 10 s ConnectTimeout with the link down), so cards said
  "stopped" with no overlay yet; and a card's own state stayed drawn under the overlay. Now the page owns it: while
  it checks, `live` is false; a stream failure is the card's own only after a snapshot came after it (the card
  asks for one at once), so a stream the dead master took shows nothing until the page knows; while it shows
  Reconnecting it tells its cards (an environment value, passed
  into each card's own hosting view), and no card's empty state or loader draws; the overlay sits on a glass panel,
  so the dimmed cards' text (a terminal's, a card header's) never runs through it. Once
  back, a card whose stream failed meanwhile loads instead of saying "stopped"; a failing stream's later retries still
  keep the panel (no blink, now checked each turn). The test downs Key Host's link (HostName 192.0.2.1), then makes
  its name unresolvable, kills its master, and checks before, during (also a workspace first shown) and after.
  Red on the old code: 42908657892 ("stopped once back") and 42912697974 ("stopped before Reconnecting"); the first
  fix still said "stopped" before Reconnecting (42912680770: the stream fails before the store's read does), and a
  cover over each card's content did not draw over its terminal (42913993186: cards live in their own hosting views,
  and an AppKit terminal sits over SwiftUI there): the panel replaced it. Green: 42915708766 (4 tests). Pictures: `~/Downloads/ovvi-research/p57f/r7/`.
- **For the user.** With a devvm-aai browser card open, sleep the Mac for a while, wake it, and reload: the page loads
  without closing the window.

### Track D

- **Cause (Markdown raw).** CodeMirror parses a file past its first screen in idle time, on a budget of the wall clock
  (3 s in every 30 s), and starts a new budget only while the editor has focus. A Rich Text card is locked, so its
  editor never has focus. A page that macOS paused in the middle of a parse (a hidden card's process, a sleeping Mac)
  spent the budget at once, and the lines past the parse stayed raw until the card loaded again. Forced on the old
  code: a 14 MB file whose page process was stopped (SIGSTOP) 1 s at a time while it parsed showed `## Part 72698` and
  `[a link](…)` raw; the same file unpaused rendered.
- **Cause (browser).** Not proven for the user's card. Forced on the old code: a page whose image never answers (a
  stalled server, a dead connection) kept "Opening Browser…" over a page that had loaded, for good, and Reload kept
  it; the card showed its page only when the load finished. Ending the page process once came back (scroll too);
  ending it again before the page loaded left the card blank. Ending the GPU or the network process changed nothing:
  WebKit starts them again. The user's unified log (24 h, a night's sleep) shows no ended process at all, but many
  "process was suspended"; a suspended process that never wakes stays possible and was not forced.
- **Fix.** The browser shows its page once the document is parsed and drew (`DOMContentLoaded` and a frame, asked in
  the app's own script world, held weakly: a hidden page draws no frame), not when every resource finished. A page whose process ends loads again by itself
  through the card's own Reload; one that ends again before it loaded shows "The page stopped working" with Reload.
  File Explorer parses the lines in view itself, 50 ms at a time, whatever has focus.
- **Fix (state).** The browser comes back at its address and scroll (WebKit's history item). File and Markdown keep
  each file's top line in the page's `sessionStorage`, which WebKit keeps across an ended process; on the old code
  Markdown came back at its top. A linked open's line no longer wins after an ended process.
- **Decisions.** A hidden card loads again at once, not when shown: WebKit loads a hidden page fine, and the
  once-per-load rule stops a loop; a hidden card ended twice shows the failure when shown. Git's diff and File
  Explorer's tree come back at their place, not their scroll. No UI test for the paused parse: whether a pause lands
  inside a parse slice is timing, so it failed only some runs.
- **Runs.** Local, old code: the kill test red only on Markdown's scroll (both cards came back); the page ended twice
  red (the loader, never the page); the paused 14 MB file raw in one run of four. New code: both new tests,
  testMarkdownCardReadsEditsSavesAndLinks, testADroppedBrowserKeepsItsPictureAndComesBack and two other browser
  tests green. A card closed right after its process ended frees its new page process. CI: 42447003583 (the kill test's Markdown lines wrapped in
  CI's narrow card; the remote browser test missed its dropped master's page once, green on the next run),
  42447943897 (all green but the kill test: CI's virtual Mac has no WebKit GPU process), then 42449897996 green (2 tests).
- **For the user.** Leave a Rich Text card beside a terminal while an agent rewrites its file, then scroll it: every
  line renders. Force Quit an "Ovvi Web Content" process in Activity Monitor: the browser or Markdown card comes back
  by itself where it was. If a browser card still goes blank after a long idle, check whether its "Ovvi Web Content"
  process shows in Activity Monitor and tell us what the card showed (blank white, the loader, or an old picture).

### Track K

- **Measure.** A Release build on a throwaway session of 30 workspaces, 120 tabs and 40 working agents, the palette's
  ~130 rows. Keys were posted inside the app (no accessibility client), and once more through XCUITest (with one).
  `-recordLatency` gave each key's time to its drawn frame, Time Profiler the main thread, and temporary counters the
  bodies made per key. The Mac's load was 60–85 throughout, so the numbers are high for an idle Mac.
- **Cause.** The list fed the lazy stack's guessed height back into its own frame (`onGeometryChange` into
  `rowsHeight`). The guess changes as rows get measured, so a key that changes every row (the first letter, the last
  ⌫ back to the groups) made the list 45 times in one turn: 320–440 ms. A section header beside its row (two views per
  `ForEach` element) made the stack make 5–8 times as many rows. Fuzzy scoring is about 1 ms a key: not a cause.
- **Fix.** The height read is clamped to the most the list shows; each row is one view; the palette reads its
  commands, places and lit row once as it opens. No accessibility client: ⌘K 74–105 → 36–79 ms; the first letter
  320–440 → 69–158 ms (later keys 8–55 ms); the last ⌫ 190–250 → 54–58 ms; the list made 45 → 1–2 times a key.
  With XCUITest attached the gain is small (first letter 184–440 → 215–330 ms): the walk below dominates.
- **Decisions.** Rows are read at open (docs: Rows at open): a title that changes while the palette is open stays old,
  and a tab or workspace closed meanwhile does nothing when chosen. Typing no longer pays for every tab and agent.
- **Left.** With an accessibility client attached (XCUITest, VoiceOver, or an app that reads other apps' windows),
  SwiftUI walks every responder of the window on each update (`AccessibilityNode.updateFocus`): about half of a key's
  time at this size. Not fixed: it is SwiftUI's, and it shrank with the number of updates.
- **Tests.** `-recordLatency` records how many times a list was made for each key; testPanelsAndSwitchesReactAtOnce
  types a letter and ⌫ and allows 3 (red on the old code: 21), and the stress test types "split" and takes it back. They
  guard the height loop only: two views per row again, or rows made per body again, would stay green.
- **Runs.** Local: testPanelsAndSwitchesReactAtOnce red on the old code (the first letter's list made 21 times), green
  on the new with testPaletteSplitsTheKeyboardCardRight. CI 42534541505: 28 palette, panel, menu and drag tests and the
  stress test, all green. On CI's Debug build with XCUITest attached the stress session's first letter still took 422 ms
  and a tab switch 478 ms: the accessibility walk.
- **Accessibility (round 2).** With a client attached, SwiftUI walks the window's focus responders
  (`AccessibilityNode.updateFocus`) a few times per update, about 30 ms each at this size. lldb showed what starts a
  walk: the accessibility nodes of rows made anew. Keyed by place, the rows in view stay and change what they show:
  the first letter 266 → 160 ms, the last ⌫ 190 → 95 ms, ⌘K 60–90 ms either way (XCUITest attached, same session).
  Tried and no gain: one kept page instead of 8, the sidebar hidden from accessibility or from hits while the
  palette is open, a typed list cut to 30 rows, a list height known without a measure. Hiding the sidebar itself
  took a further 35–40 % off (its rows' responders are walked too); that is Track B's sidebar, left as it is.
- **Runs (round 2).** CI 42543823173: the same tests and the Open Session ones, 29 green. On CI (Debug, XCUITest
  attached) testPanelsAndSwitchesReactAtOnce's first letter went 535 → 172 ms and its ⌫ 461 → 121 ms; the stress
  session's last ⌫ 375 → 162 ms. A review caught `scrollTo` by place finding a keycap's Int id first: keycaps are
  keyed by their text.
- **Left (round 2).** A list that grows past the panel's height ("spl" → "sp", ⌫ from 12 rows to 45) still costs
  about 200 ms with a client and 70 ms without; the other keys cost 25–160 ms and 20–110 ms. Without a client the
  Mac's load (60–85) and the 40 agents' redraws set a floor of 20–30 ms even for a one-row change.
- **For the user.** Open ⌘K while agents work and type a first letter, then ⌫ back: each should draw at once.

## Round 2 (items 18–27)

Screenshots in `.build/fb57/`: `r2-4.02.42.png` (the ⌘N picker stuck on "Reading sessions…" for This Mac and
devvm-aai), `r2-1.09.55.png` (a floating card's Back button: more space above than to its left), `r2-1.16.42.png` (a
chat bubble's time close to its text).

18. "cmd+n window stuck at reading sessions" (Track A).
19. "can we improve cmd+d splits animaiton, i see there are frame drops sometimes especially when full screen tui or
    any plugin is there, do a full stress testing and measure cmd+d and cmd+shift+d splits and profile where actually
    it is getting slow and see if we can make it as smooth as posssible" (Track J, new).
20. "and this ctrl+ - and ctrl+shift+- for going back and forward is not intuitive at all, what does vs code generally
    uses to jump back and forward, can we use something that, we need some intuitive shortcuts, not a bit random ones"
    (Track E).
    - VS Code on macOS uses exactly ⌃- / ⇧⌃- (Alt+← / Alt+→ elsewhere). The Mac-native pairs are ⌘[ ⌘] (Finder,
      Safari, Chrome; Ovvi's pane selection, which the user asked back in phase 56) and ⌘← ⌘→ (Safari, Chrome).
      Decision: ⌘← ⌘→ are Back and Forward over File Explorer and Git, the editor included while it is locked or
      read-only; only where the caret edits text do they move the caret. ⌃- / ⇧⌃- go. Mouse back/forward buttons
      and the swipe keep working.
    - Then the user: "okay let's stick to the vs code one itself then". ⌃- / ⇧⌃- stay Back and Forward; nothing
      changes for item 20.
21. "so on the slight increase in padding we did in floating panels, we might need to reduce a bit, basically left
    and top padding should be equivalent so it looks symmetric you know. right now i see slightly more top padding
    than left padding when i hover on the back button" (Track E).
22. "cmd+k search has become quite laggy with i think many options now, can we make it more snappy, stress test,
    maeasure and improve" (Track K, new).
23. "empty states are good now, one thing is when remote machine is disconnected, we see some icon right, idk what
    that icon means, can we use a relevant disconnected icon instead" (Track A).
24. "spacing can be improved for the timestamp thing in messages, its bit too close to message, same for assistant
    message as well, also don't show that show tui button on error, that's weird" (Track I).
25. "for settings, let's try out option b, and also can we add some padding between search and first menu option,
    only slight increase" (Settings icons).
26. "in markdown for the lock, can we have better icon? like the lock is not intuitive on what it means" (Track E).
27. "for the sidebar, your design is good, increase gap between workspaces a bit, and show time as well for statuses,
    no need of new agent button on top, let's skip that, for the unselected workpsaces, expanded one should have a
    border without glass effect, one selected should have glass  effect, rest go with your recommendations"
    (Track B: build).

### Track J findings

- **How it was measured.** The split record (`-recordLatency YES`: 0.8 s of display-link frames at 120 Hz from the
  split, with the main thread's CPU per frame) and the on-demand `testSplitsKeepTheDisplayRate` (two ⌘D and two ⇧⌘D
  beside a shell, a program that redraws its whole screen 30 times a second, File Explorer, Git, Markdown, a browser,
  and among six panes). XCUITest's accessibility client took about a quarter more of the main thread, so the numbers
  below come from the Release app with no XCUITest, clicking Split Right and Split Down by posted mouse events, before
  and after in turns (8 splits a scenario each), at a load of 20–80. Time Profiler and `sample` for where the time
  goes; a small SwiftUI probe app for single causes.
- **Cause: no hot spot of the app's own.** A split took 190–250 ms of main-thread CPU in its 0.8 s. The split's own
  turn held the first frame 32–41 ms (a third of it the new card's chooser list); each frame of the slide spent
  5–20 ms in SwiftUI layout of the resizing cards and AppKit's hover, tracking-area and window-drag-region passes;
  herdr's answer (snapshot apply, the new card's terminal, the menus: 30–60 ms) could land inside the 130 ms slide.
  A kept page out of view drew all its cards again at each split change (40–100 card bodies a split under XCUITest).
  libghostty, the PTY resize and the web views cost little: they already keep their size until the slide ends.
- **Cause: the Glass look.** Gaps with little CPU are the render server: Glass composites the window's two blurs again
  under every moving card. Classic had about half the hitches in the slide (2 against 4), with the same CPU.
- **Fix.** The chooser list shows once the card slid in (its keys work before); herdr's snapshot is applied after the
  slide; the window is not movable during the slide (AppKit then skips the drag region, about 15 % of a probe's
  frames); hidden kept cards do not read the shown tab's tree, the newest card or the keyboard (−20–40 % bodies,
  −10–15 % CPU with kept pages).
- **Runs (before → after, medians; first frame and CPU are means).**

  | Scenario | first frame ms | hitches in the slide | worst gap in it ms | p50 / p95 ms (0.8 s) | hitches / 0.8 s | CPU ms |
  |---|---|---|---|---|---|---|
  | shell | 37 → 25 | 4.6 → 4.2 | 29 → 25 | 8 / 21 → 8 / 17 | 11.5 → 11.9 | 190 → 173 |
  | full-screen TUI | 35 → 22 | 4.4 → 4.1 | 29 → 23 | 8 / 22 → 8 / 18 | 12.0 → 12.4 | 199 → 176 |
  | File Explorer | 32 → 20 | 5.4 → 4.5 | 26 → 22 | 8 / 19 → 8 / 17 | 10.8 → 10.9 | 203 → 188 |
  | Git | 33 → 20 | 5.1 → 4.0 | 23 → 24 | 8 / 16 → 8 / 16 | 10.8 → 10.5 | 200 → 188 |
  | Markdown | 35 → 20 | 4.5 → 4.1 | 26 → 25 | 8 / 17 → 8 / 17 | 9.1 → 9.6 | 197 → 177 |
  | browser | 37 → 23 | 4.4 → 4.8 | 21 → 24 | 8 / 18 → 8 / 18 | 10.0 → 11.0 | 201 → 180 |
  | six panes | 41 → 27 | 4.4 → 4.0 | 35 → 33 | 8 / 24 → 8 / 24 | 14.0 → 14.0 | 247 → 227 |

  The slide starts 12–14 ms sooner and its worst steps are a little shorter; the hitch counts barely move, since most
  are the render server and per-frame framework work, and the load of other agents moved them by as much. With kept
  pages (the UI test, 7 kept pages by the last scenario) the CPU went 234–364 → 210–328 ms.
- **CI.** Chosen tests 42544067365 green, executed 8 (the chooser, quick splits, ⌘D latency, layout motion, the
  flicker check and the new measurement test). The review's one should: a hidden card keeps its last lit look, so a
  kept web card's theme does not change at each tab switch.
- **Tried and dropped.** Making the cards' per-frame size writes stateless (no fewer bodies); a render-only slide
  (offset and an animated clip, layout once at the end) in the probe: no clear gain for a rewrite of the layout and
  its motion tests.
- **For the user.** Split with ⌘D and ⇧⌘D in Glass and in Classic, beside a busy agent: the slide should start at once
  and the chooser fade in as the card lands. If Glass still stutters where Classic does not, its blurs are the cost:
  a lighter Glass while cards move is a look decision.

## Round 3 (items 28–30)

Screenshot `.build/fb57/r3-6.05.46.png`: a terminal line naming `~/Downloads/ovvi-checklist-57.md`, a file the user had
deleted; ⌘-click and ⌥-click on it opened nothing.

28. "so i started doing cmd+click and option+click, on the md file but nothing opened, then i realised i removed that
    file. we should probably show a toast saying file not found or something like that, instead of silently not
    opening the pane" (Track C).
29. "on the fetch, pull and push on the workspaces part, where you can right click and do right, it does show the toast
    pulling etc, but that goes away instantly as soon as pull is done, so its usually like stays for less than a sec,
    and i think the toast would be better, if it shows like pulling with a spinner on its left and that spinner turns
    to green checkmark icon or something when fetch/pull/push is finished, and stays there for a couple of seconds and
    then hides, that would give better overview to user, instead of quickly showing and hiding" (Track M).
30. "let's rebrand workspaces to spaces, so herdr recently calling workspaces as just spaces and i like that, so let's
    check in all our ui where we refer it as workspaces and update it to space(s)" (Track L, new).
    - Every user-facing string (menus, ⌘K, tooltips, empty states, Settings, help, the `ovvi` CLI's help, the skill)
      and the design docs say space(s). herdr's API names (`workspace_id`, `workspace.*`) and code identifiers stay.

### Track C, round 3 (item 28)

- **Cause.** Every open of a file that is gone stopped silently: the terminal let a path that is not there go to the
  program (so a word that only looks like a path stays inert), and a plugin's open (a Markdown link, a Git diff's file,
  a tree row) went on to a card on a missing file. `ovvi open` answered the CLI only.
- **Fix.** One notice, "File not found: ‹path›" (warning tone, the home folder as `~`), from the store. The terminal
  gives it for a link that names a file for sure: a `file:` link, or an absolute or `~` path whose name has an
  extension; a plain word (`/reload`) stays the program's. A plugin's open of a path (or of an HTML file's `file:`
  page) checks the path on the card's machine first. ⌘K's Open File and `ovvi open` say the same.
- **Decisions.** A relative path in the terminal (`notes.md`) stays inert when gone: libghostty links many plain words.
  `ovvi open` shows the notice only when typed in a shell: an agent's open (often a probe) gets its CLI error alone.
- **For the user.** ⌘-click and ⌥-click a terminal path to a deleted file, and a Markdown link to one: a notice says
  "File not found: ~/…".

### Track L

- **herdr's words.** The herdr 0.9.5 TUI says Spaces (its sidebar, `ui.sidebar.spaces`, "grouped by space"); its
  CLI, API, config keys and skill still say workspace. Ovvi follows the TUI: Space(s) in every surface the
  user sees, workspace only where herdr's API is named.
- **Fix.** Menus, ⌘K commands and their group, the title-row button's help and accessibility label, the sidebar's
  empty states and ghost row, the close sheet, the rename prompt, Open Session's delete text, the drag type's
  description (Info.plist) and every design page's prose. The glossary has a `space` row saying herdr's API still
  says workspace. The `ovvi` CLI, the skill, the plugins and Settings had no such word.
- **Decisions.** Swift identifiers, accessibility identifiers (`workspace.w1`, `sidebar.new-workspace`, `workspaces.*`),
  herdr method and field names, `herdr workspace` commands and the playbook's history stay as they are. A ⌘K
  command's identifier is `palette.command.<title>`, so those follow the new titles in the tests. "Empty space" in
  the drag docs became "empty area", so space means one thing. New, Close and Rename Space keep "workspace" as a ⌘K
  keyword, since herdr's CLI and skill still teach that word.
- **Runs.** Chosen tests 42551254721 green, executed 6 (the tests that click the renamed menu items, palette
  commands and Keyboard Shortcuts rows).
- **For the user.** Look over the sidebar's right-click menu, File ▸ New Space / Close Space, ⌘K "space", and the close
  sheet of a space with worktrees.

### Track M (item 29)

- **Cause:** the sync's notice was a plain information notice that went the moment git ended, often under a second.
- **Fix:** the one notice capsule has two more tones: `progress` (a small spinner) and `success` (a green
  `checkmark.circle.fill`). "Pulling ‹name›…" shows the spinner while git runs. When git ends, the git line is read
  again, then "Pulled ‹name›" with the check shows for 2 s, or git's message in the error tone for 4 s.
- **Decisions:** after × or a newer notice, the check does not show, but an error still does. File Explorer's status
  bar is left as it is: its buttons show their own busy state, and it uses the plugin card's toast only for errors.
- **For the user:** right-click a repository's row and pick Pull: the spinner, then the check for about 2 s.

### Runs (Track M)

- The test slows upload-pack by 3 s to see the spinner. It was red on the old code ("Information" is not "In
  progress"), and green on the new code.

## Round 4 (items 31–43)

Screenshots in `.build/fb57/`: `r4-6.52.26.png` (floating Git diff), `r4-6.52.37.png` (floating Git history),
`r4-6.53.14.png` (floating File Explorer), `r4-6.54.01.png` (floating browser): the space above the top bar is now right,
the space under it is not the same. `r4-6.58.31.png`: a chat bubble whose text sits closer to its top edge than to its
side.

31. "right now when no window is opened in ovvi, we still connect to default mac session by default, we shouldn't
    automatically connect to any session by default, on cmd+n or opening ovvi with all herdr installed and everything
    should open the new session page, and let's revamp the open session window, it shouldn't say open session, it
    should have ovvi logo and name with options for session or add or edit machines etc stuff, also new session window
    should be maximised by default and default window should be maximised by default as well. think through what should
    go through new window view, it should be minimal but should have quick acees things so user can connect to a
    session or machine quickly" (Track A).
32. "can we archived sessions search, like search by title is fine, when we expand archived sessions show a search
    below the title and the list below should be updated based on the search, also for archived sessions as well can
    we add a border around similar to inactive workspaces, no need of glass effect though, just the current design we
    have for inactive workspaces which are expanded. also the filter we have for archived sessions right now where we
    filter by agents, let's keep that within the new search bar." (Track B).
33. "let's increase spacing a bit more between workspaces, they are bit too close to me" (Track B).
34. "let's expand all spaces showing their agents in sidebar by default" (Track B).
35. "let's actually drop pinned tabs feature for now, its not fitting well overall in the sidebar i feel" (Track B).
36. "for agent tabs with no title and grabs user prompt as title, on tab hover it shows multiple lines, let's limit the
    title to single please, no multiple lines needed." (Track B).
37. "for the workpaces in sidebar, lets show the subtle border even when the agents things are not expanded, it looks
    weird with few having borders and few not having, so basically add borders to all and increase spacing a bit"
    (Track B).
38. "let's remove the shortcut keys we show on tabs and worskpaces on holding cmd or ctrl+command, its bit distracting
    and add very less value i feel" (Track E).
39. "one more thing i noticed with browser plugin, i cannot zoom in the page using trackpad pinch and zoom gestures, in
    regular browser, you can pinch and zoom a page which basically maginfies the page, not increasing font one, just
    regular magnify zooming into part of page, chromes does that, can we introduce something like that with our
    browser plugin?" (Track D).
40. "and with floating panes, we are lackign symmetry with upper padding and lower padding in mostly all plugins, upper
    padding is good now, but equivalent lower one should be there, you are lacking the attention to detail, check these
    screenshots and improve: <r4-6.52.26, 6.52.37, 6.53.14, 6.54.01>, and similarly for chat view as well:
    <r4-6.58.31>, top paddding is less here" (Track E).
41. "and one more improvements when multiple sessions are there in a window, let's keep archived sessions stick like
    filter, as it will be same for a device and it won't change with sessions, and above archived sessions let's bring
    back the dots indicating which session we are on which we removed it." (Track B).
42. "and one more thing libghostty 1.0 has released: https://mitchellh.com/writing/libghostty-1-0, let's upgrade to use
    it, also make sure what flags to use etc, and any improvements that we can take from altest upgrade etc" (Track N,
    new).
43. "and finally now that we added many features, scrapped few more featurees etc, lets try to revisit all code with
    one agent, goal is to make sure the code is clean and doesn't have traces of old code or unnecessary complexities
    from the old code, simplify where possible, cleanup unnecessary comments, comments are needed only when something
    cannot be explained by code and needs there to avoid confusion, let's avoid random unnecessary comments or
    unnecessary or weird abstractions and once all done, do a full ci runs and make sure everything is good" (Track O,
    new, after every other track lands; then the phase's full runs).

### Track D, round 4 (item 39)

- **Cause.** Browser cards never turned on WebKit's `allowsMagnification`, so a pinch and a two-finger double tap did
  nothing. Nothing of the app's takes magnify events: the session swipes watch scroll events only, and overview tiles
  show pictures.
- **Fix.** Browser cards magnify on a pinch around the fingers, and smart zoom works with the trackpad's Smart zoom
  setting; the layout stays (no reflow), as in Safari. ⌘0 resets the magnification with the page zoom, also in a
  floating window, whose ⌘+ ⌘− ⌘0 now act on its own browser card (they took the main window's keyboard card).
- **Decisions.** No magnification on plugin cards or `window.open` popups.
- **Runs.** testAPinchMagnifiesABrowserPage (a synthesized trackpad pinch, `scripts/pinch.swift`): red on the old code
  (the text's frame stayed 93 x 18 pt), green after in 12 s. Pictures: a line pitch of 68 px at rest, 178 px after the
  pinch (2.6x), 68 px after a pinch on the old build. CI 42559293377 green (3 tests).
- **For the user.** Pinch a browser card's page and two-finger double tap a paragraph (Smart zoom on in System
  Settings ▸ Trackpad); ⌘0 undoes it, also in a floating browser window.
- **Cause (gestures into the user's Ovvi).** The scripts that post events (pinch, swipe, drag, press, file and text
  drags) checked only that a window named Ovvi was under the point, which the user's own Ovvi passes. Now each refuses
  unless the front window below the Dock's level at every point is the tests' app's; the helper passes its pid (the
  newest Ovvi on one of the helper's sessions, as usage, sample, heap and web-kill now find it). A dry run with the
  user's Ovvi in front refused all four scripts before any event. macOS's UI-test overlay (AutomationModeUI) and, on
  CI, a full-screen Dock window sit over the app and let events through, so only levels below the Dock count.
- **Cause (the floating restore test).** newTab waited for herdr's tab, not for the space's row; this test launches the
  app itself and asked before the window connected. Under that: its first launch restores whatever windows the last
  Ovvi saved (the bundle id's saved state is shared by every Ovvi on the Mac and by earlier tests, also ones launched
  with -ApplePersistenceIgnoreState), each as its own window on -session, so the row showed twice. newTab now waits
  for the row; the two restore tests start from no saved windows (forget-windows, CI only) and skip on a Mac.
- **Runs (follow-ups).** CI 42572730463 green (6 tests: both restore tests, the pinch, press, file drop and swipe
  tests); earlier dispatches failed in setup (GitHub's release download answered 504) or showed the Dock's window.
- **Cause (Debug builds were the user's app).** Debug builds (`make run`, the UI tests, CI) carried the installed
  app's bundle id, so they shared its defaults, saved windows, notifications, login item and `ovvi://` claim: tests
  restored the user's windows, and Launch Services held 124 old DerivedData builds that could take the user's
  `ovvi://` opens (now unregistered; only `~/Applications/Ovvi.app` handles `ovvi://`).
- **Fix.** A Debug build is `Ovvi Dev.app`, `dev.ovvi.app.debug`: it claims `ovvi-dev://` (it still takes `ovvi://`
  sent to it by path, as tests do) and keeps `~/.config/ovvi-dev` and `~/Library/Logs/Ovvi Dev`. The executable stays
  `Ovvi`, so the menu bar reads Ovvi. The restore tests now clear the Debug build's saved windows on a Mac too and run
  there. Shared on purpose: `~/.cache/ovvi` and `~/.local/state/ovvi` (the sessions' files), herdr's server jobs.
- **Runs (bundle id).** CI 42577130231 green (6 tests: About, the Dock folder drop, the `ovvi://float` open, both
  restore tests, the pinch); the same 6 green locally, the restore tests no longer skipped.
- **For the user.** A Debug build now asks once for notifications as Ovvi Dev. Old copies of Ovvi built before this
  keep the old id until deleted.

### Track B, round 4 (items 32–37, 41)

- **Built.** Spaces start unfolded and a fold sticks (`agentsOpen` keeps "folded ‹id›" lines now; the old unfold lines
  go at launch). Every space row not selected has the 1 pt border, folded or not; the selected one has the glass.
  Rows are 10 pt apart (pictures of 8 and 10 pt; 10 picked). Pinned tabs are gone: the sidebar part, the pill's pin,
  Pin Tab / Unpin Tab, `tabPins` (removed at launch), the move bookkeeping, docs and the test. A tab's hover card
  keeps one line per pane: the 3-line prompt under an agent's name is gone (the title fades, as every title).
  Archived Sessions sits under the pages, the machine's (one fold per machine, `‹machine› archived-sessions`), in a
  space row's border, with a search field (title and folder; Esc clears; a fold clears it) and the agent menu at the
  field's end; the footer filter no longer reaches it. The page dots are back above it, centered on the rows.
- **Measured** (2x pictures): between two rows 12 px = 6 pt before, 20 px = 10 pt after; borders 2 px = 1 pt; the
  Archived header 60 px = 30 pt; its chevron and a row's both centered at x 549.5 px; the Archived and agent tiles
  both at x 36 px = 18 pt; the search field 8 px = 4 pt inside the border; the dots 6 pt, centered at the rows' 149.5
  pt, 11 pt from the list's end and 11 pt from Archived Sessions.
- **Review.** Round 1: a blocker (the migration dropped the new Archived fold line at each launch), five should-fix
  items and eight nits, all fixed; round 2 clean.
- **Runs.** CI 42559593130: 21 of 22 chosen tests green; `testTheSelectedRowScrollsIntoView` measured a long list's
  end at the last space's header, which now has its agent's line under it (unfolded), so it measures that line.
  CI 42561566780 on the rebased head: that test and five sidebar tests, 6 executed, all green.
- **Pictures**, before (main a2172480) and after, dark and light, with the numbers:
  `~/Downloads/ovvi-research/p57b/r4/index.html`.
- **For the user.** Fold a space and relaunch: it stays folded, the others unfolded. Open Archived Sessions, type in
  its search, pick an agent from the menu at the field's end, then swipe or click a dot to another session: the shelf
  stays where it is, open, with the same list.

### Track N (item 42)

- **What 1.0 is.** libghostty 1.0 (tag `vt-1.0.0`) is libghostty-vt: a stable C ABI for a terminal's state (parse,
  screen, scrollback, input encoding, selection, Kitty graphics data), with no renderer. Its official XCFramework
  (`GhosttyVt`) cannot replace GhosttyKit: Ovvi needs Ghostty's embedding API with its Metal renderer, fonts and AppKit
  view, which 1.0's ABI promise does not cover. Moving would mean drawing the cells ourselves. herdr is the program that
  runs on libghostty-vt: scrollback, OSC, input modes, IME results and resize reflow are herdr's, and Ovvi draws herdr's
  frames.
- **Fix.** libghostty-spm 2.2.2026100801 → 2.2.2026110702, its latest (Ghostty 042b16b6, Nov 2: 479 upstream commits
  newer than our pin, 165 older than `vt-1.0.0`; the package has no `vt-1.0.0` build yet). It brings faster print paths,
  Kitty graphics from the render state, DEC 2026 kept across a resize, copy without a TUI's padding, the left or right
  Option for "Left acts as Meta" (before, both read as left), and no GNU libintl (LGPL): its license left the
  Acknowledgements, which settles phase 33's open point. Its AppKit view now takes drops itself and refused file
  promises, so the card keeps its own file and image drops (remote copies, `TemporaryItems`, promises) and hands text
  and links to the package, which pastes them.
- **Flags.** 1.0's build flags (SIMD, system simdutf and Highway, features compiled out) apply only to a build of
  libghostty-vt; a prebuilt GhosttyKit has none. Config kept: `keybind = clear`, no padding, `scrollback-limit = 0`
  (herdr's), transparent background, the selection colors, `macos-option-as-alt`, `copy-on-select = clipboard`. Ghostty's
  defaults fit the rest (Metal, vsync, `link-osc8`, `alpha-blending = native`).
- **Kept workaround.** ⌥ over a link still sends libghostty ⌘ (Track C): Ghostty still hard-codes the link hover to
  ⌘ or ⌃ (`hover_mods = ctrlOrSuper`), and its `link` config "can't currently be set". libghostty-spm's open pull
  requests #102 and #103 (hover link and open-URL hooks) do not change that.
- **Runs (Release app, no XCUITest, old and new in turns, 2 rounds, load 200–300).** `cat` of a 32 MB file: 0.38–0.51 s
  before and 0.39–0.45 s after, Ovvi 0.12–0.14 s of CPU both (herdr sends frames, so the app parses screens, not the
  file). 10 splits and closes: 3.70–3.73 s of CPU before, 3.78–3.86 s after; 20 resizes 3.69–3.75 s, 3.66–3.70 s: the
  same. Memory: 124–125 MB with one pane both; seven panes 183–184 MB before, 175–177 MB after (9.8 → 8.6 MB a pane).
  Idle, seven panes, 10 s: 0.24–0.26 s of CPU before, 0.09–0.12 s after: the package's cursor timer no longer redraws
  surfaces that are not focused or do not blink.
- **Runs (CI).** Chosen tests on the upgrade: 42556540631 green, executed 50 (Terminal, Pane, Pane input, Replace, Drag,
  Reveal, a tab's flicker, selection and cursor looks, links, HTML, Find, font size). On the drop fix: 42558841860
  executed 6, the remote file drop and the drags green; the new text drop pasted but its check missed the pane's wrap,
  fixed and green locally.
- **Decisions.** The package dropped its `font-thicken = true` default, and Ovvi takes Ghostty's (off): text draws as in
  Ghostty and Terminal, thinner than before, most visibly light on dark. Sheets in
  `~/Downloads/ovvi-research/p57n/` (`sheet-font-thicken.png`, `zoom-dark-before-after.png`).
- **For the user.** Look at the font sheets: `$0.withFontThicken(true)` in `TerminalFont.swift` brings the heavier text
  back. Drop text, a link and a browser image (a file promise) on a terminal, and a file on a remote card. With "Left
  acts as Meta", the right Option types characters.

## Round 5 (items 44–49)

The user keeps round 4's pane padding and the thinner terminal text (no font-thicken): "i am okay to keep the changes
you did, no need of reverting them".

44. "chat view sometimes doesn't work with relaunch with caht, like i do relaunch with caht, and it still relaunch with
    caht button instead of opening in chat view, this doesn't happen on this device, i installed ovvi on non meta device
    where the agents don't have any meta launchers there i noticed this issue, make the relaunch with caht and detecting
    chat options more robust and improve it better" (Track G).
45. "and the cmd+d is still lagging man, like its very evident you know, can we figure out better way to improve it? at
    least one point i noticed is this happens mostly when our new pane thing opens up, when some other browser pane or
    something i open i don't generally notice, check if there's anything heavy in our new pane view etc and improve it"
    (Track J).
46. "so work on this: \"Find all of the implicit state machines in my app. Make the best decision that will elevate all
    three: the user experience (UX), developer experience (DX), and agent experience (AX) always, without breaking
    anything.\" go deep and give me a detialed html report on what changes we can make overall, do not make any
    changes, just analyse and report" (Track P, report only).
47. "help me build another report showing multiple ui mockups for landing page for ovvi, follow this playbook:
    https://x.com/DanKulkov/status/1955909008973513043?a=85jZfizHnUSgpyZGmHE. give me at least 5 variations, all have to
    be minimal, developer focused, with screenshots or video recordings etc. make it modern and minimal without slop
    like look, only html report with all mockups again, no code changes" (Track Q, report only).
48. "can we have an option in settings to provide an option on what to open on new pane, default is our new pane view,
    or user can select different options as default, can be agent, file explorer or git etc plugins" (Track R).
49. "one more thing when herdr is not installed, we currenly show empty state with install button right, let's have
    some short info on why herdr has to be installed, like ovvi relies on herdr as runtime or something like that, keep
    it concise and fit well to the overall ui" (Track A).
- "only once all these are done, invoke our cleanup things and ci check i mentioned earlier": Track O (item 43) starts
  after every track of rounds 4 and 5 has landed.
50. "in classic view, the borders of ui elements are not quite visible, like i mean in glass view all components are
    clearly distinct, but in classic view specfiically dark mode, like tabs, workspaces and panes can have may be very
    subtle borders to improve them? check all components in classic view and improve them overall and make the
    components better" (Track T).

### Track Q (item 47, report only)

- Report: `~/Downloads/ovvi-research/landing/index.html`, five pages beside it (`manual`, `window`, `terminal`,
  `letter`, `spec`), shared media in `assets/`, renders in `renders/`. No app code changed.
- The playbook (Dan Kulkov's X post) loaded without a login; its 21 steps and how each page meets them are in the
  report. Ovvi has no testimonials yet: the pages use only true proof (herdr's GitHub stars, the four chat agents, the
  UI test count, no servers) and dashed, labeled quote slots.
- Pictures: a Debug build of `15310ee3` as its own instance on `ovvi-dev-p57q`, with `-configFolder`, `-machines
  '[]'` and pinned settings. The agents are `scripts/claude-stand-in.py` with scripted turns (a copy in `/tmp`), so
  the chat view, Git card and states are real app output but the replies are not a live model's. Recorded with
  ScreenCaptureKit on that window only.
- Found: ScreenCaptureKit's `SCScreenshotManager` hung after about 15 min of use (every later call); `screencapture
  -l` kept working. A launch with `open -n` saves its windows into the shared `$TMPDIR/dev.ovvi.app.savedState`
  even with `-NSQuitAlwaysKeepsWindows NO`; delete it after a run. A login shell under load missed the 3 s herdr
  lookup ("herdr is not installed"); a fixture login shell (`SHELL=…`) fixed it for the run.
- Incident: `pkill -f <pattern> -P 1` on macOS took `-P` and `1` as patterns and killed many of the user's
  processes (lesson `eb845b4a`). Kill exact pids only.

### Track R (item 48)

- **Fix.** Settings ▸ General ▸ Panes has "New panes open": New Pane (the chooser, the default), Terminal, each agent,
  Browser, File Explorer, Git and every plugin with a chooser row (`newPaneOpens`, a row's id). Every new shell pane
  (⌘T, ⌘D, ⇧⌘D, Split Left and Up, the `+` buttons, the menus, ⌘K, every New Space, a folder on the Dock, a started
  session's first space) makes that pick on its chooser at once, through the chooser's own `pick`: the list never
  shows; an agent or a plugin shows its loader on the stand-in until herdr made the pane. The New Pane view is
  untouched.
- **Decisions.** ⌥ held as you click to make the pane shows the chooser. No ⌥ key: ⌥⌘D is macOS's Turn Dock Hiding
  On/Off (the system takes it) and ⌥⌘T is Open Session; from the keyboard, ⇧⌘R on the new agent, browser or plugin
  pane gives the chooser. ⌥ is read as the pane is made, before any await (New Space: before herdr's answer). Not for
  Replace Pane, Open … Here, Start Agent Here, Resume (it picks its own agent) or the CLI (no plain new pane). An agent
  the machine lacks, or a plugin removed since, gives the chooser.
- **Fix (follow-ups).** Keys typed after a Terminal or agent pick, before the new terminal has the keyboard (herdr's
  answer, the snapshot, the focus), wait on the card (`holding`) and then go into that terminal's own ordered input
  queue: none reaches the old card, also after a fast ⌘D or ⌘T with a fixed Terminal. A holding chooser counts only
  for the keys: every view shows the made pane. A plugin pick beeps. With a fixed pick, the splits and New Space have
  ⌥ alternate menu items ("Split Right and Choose…"), and the setting's note says to hold ⌥.
- **Decisions.** SwiftUI's `modifierKeyAlternate` gives an alternate the item's key plus ⌥: ⌥⇧⌘D and ⌃⌥⌘T work,
  macOS takes ⌥⌘D while its Dock shortcut is on, and New Tab has none (⌥⌘T is Open Session). Replaying the held
  NSEvents reordered them (libghostty sends text later than named keys) and ran the key monitor again: they go in as
  herdr keys and text instead, so dead keys and Option as Meta do not apply to them.
- **For the user.** Pick a default, then ⌘D, ⌘T and New Space; ⌥-click a `+` or a split button, or hold ⌥ over View
  ▸ Pane, for the chooser. With Terminal fixed on a remote machine, type right after ⌘D: the keys land in the new pane.
- **Runs.** Chosen tests on main 54759f43 (run 42569693100): 4 green, the fixed-pick test red on a test race (the
  chooser's pane closed as its label was read); fixed, green on 62d86ca2 (run 42570554962). Earlier attempts died on
  GitHub's 504s for herdr's and libghostty's downloads.
  Follow-ups: chosen tests on 962c41cc (run 42575992688), 7 of 8 green; testPickingAnAgentStartsItBehindTheLoader red
  with herdr reporting the stand-in: chat's `settle` (2459900a) waits up to 10 s for launch pids a shell-function
  stand-in never has (Track G's). All 8 green locally.
- **Cause (stray tab).** `ovvi open git .` beside a pane: herdr's split runs no command, so the labeled pane came as a
  new tab and moved into the split; a snapshot in between drew the temporary tab ("Git api") for about 0.2 s. **Fix:**
  the pane hides by its label outside the split's tab until a snapshot after the move has it in place (`Ahead.Moving`,
  as Replace Pane hides), and a ⌘T's stand-in never claims a tab with only hidden panes. A pane with no label (Resume
  beside, `ovvi agent` beside) is split in place with `pane.split`'s `cwd`: no temporary tab. **Runs:** the new test
  was red on the old code locally (round 0 saw 3 tabs for 2) and green with the fix; chosen tests on CI: run 42915437211
  (4 green, the new test lost its card id to the narrow shell's wrap; fixed), then run 42918005407 green.

### Track T (item 50)

- **Cause.** Classic dark drew no edge round a card (the card #222 on the window #1e1e1e, +4 levels, 1.05:1), its
  selected tab and row pill was a flat white 0.045 (+10, 1.13:1) and the tab bar had no track. Glass dark, which
  reads well, measured: card edge +22 (1.31:1), track +8, selected pill rim +100.
- **Fix.** Classic only, in the `Look` tokens: cards get a hairline outer stroke (dark white 0.1 at 0.7 pt, 0.16 at
  0.8 pt on the keyboard card; light black 0.12 → 0.14); the dark pill is white 0.07 with a 1 pt edge at white 0.12;
  the tab track shows in Classic dark too (primary 0.05). `ChromeStyle` moved to its own file (Style.swift was at 400
  lines).
- **Decisions.** Two strengths drawn: very subtle (card +14, 1.19:1) and subtle (card +23, 1.36:1, pill +49, track
  +10); subtle picked in dark, as close to Glass's 1.31:1 card edge without passing it anywhere. Classic light already
  read at Glass's level (card edge 1.31:1), so only its card stroke steps up (1.37:1). Unchanged after measuring:
  space rows and Archived Sessions (primary 0.14: +20 in Classic dark, Glass +22), the filter field, panels, the
  palette, hover card and notices (the shared system glass: fill 1.38:1 and a dark outline in Classic dark), the
  floating window (its card fills the window) and Settings (system controls, pixel-identical). Glass's code paths
  are untouched; its before and after pictures differ only by timing (badges, cursor).
- **Runs.** CI 42568085283 (chosen: the four look tests, both Classic scene tests, the overview test): 7 executed,
  green (two reruns of a 504 on herdr's download, no test ran then).
- **Pictures.** `~/Downloads/ovvi-research/p57t/index.html`: the strengths sheet and before/after in all four looks
  with the measured numbers; also a chat card's Chat | TUI switch and the overview.
- **For the user.** In Classic dark: the cards, the selected tab and space row and the tab track should stand apart
  from the window without looking heavy; Glass should look the same as before.

### Track J, round 5 (item 45)

- **Cause.** New Pane's list waited for the 130 ms slide and then faded in over 0.15 s (round 2 had moved it out of
  the split's turn). It showed 0.25–0.3 s after ⌘D, on a card that slid in empty, while a browser card slides in with
  its page: the lag the user saw. Nothing else in New Pane is heavy on appear: the agents are found once per window,
  in the background; rows, numbers and labels are microseconds; program icons show only with Agent open; the folder
  line reads no disk; no herdr call waits on it. The list's dearest part was its scroll view (an AppKit view of its
  own): a probe app put it at a third of the list's cost; tooltips, hover and VoiceOver focus at about 5 % each.
- **Fix.** The list comes with the card from the split's turn. A scroll view only on a card lower than the list (at
  once, no cross-fade, when Agent's opening crosses that height). A test splits a chooser card until it is short
  and checks its selected last row stays in view (it passes without a scroll on the new scroll view's appear too, so
  there is none).
  herdr's snapshot still waits for the slide. The split record gains the steps after the key (snapshot applied,
  list, surface, ready, program) with the CPU of their frame.
- **Runs, without an accessibility client** (Release, clicked by a script, before and after in turns, 8 splits each, Glass,
  a load of 330 falling to 40). Before → after; the browser row is `ovvi open --beside`, for reference.

  | Scenario | first frame ms (its CPU) | list shows | worst gap 0–0.6 s ms | hitches 0–0.6 s | CPU 1.2 s ms |
  |---|---|---|---|---|---|
  | shell | 24 (20) → 35 (34) | ~0.3 s → first frame | 36 → 36 | 11.5 → 10.1 | 229 → 226 |
  | File Explorer | 20 (19) → 34 (32) | ~0.3 s → first frame | 32 → 26 | 11.0 → 9.9 | 236 → 246 |
  | six panes | 31 (28) → 46 (43) | ~0.3 s → first frame | 40 → 42 | 10.2 → 9.9 | 254 → 256 |
  | browser beside | 35–42 (32–39) | its page with the card | 24–28 | 8.5–8.8 | 174–181 |

  The first frame now costs what a browser split's costs; the list's own frame (21–25 ms CPU here) is gone from
  after the slide. The hidden shell's terminal surface (16–27 ms) lands after the slide, with herdr's snapshot; its
  `ready` frames cost 2–4 ms.
- **Runs, with an accessibility client** (CI's VM under XCUITest, 60 Hz, `testSplitsKeepTheDisplayRate`): main
  42573608915 and this change 42573612578 (green, 7 tests). The first frame comes later on the VM (shell 99 → 156 ms,
  the list built with the card), and the slide's hitches went down (shell 1.0 → 0.2, File Explorer 0.8 → 0). The
  record window grew from 0.8 to 1.2 s, so totals do not compare.
- **Pictures.** `~/Downloads/ovvi-research/p57j/r5/`: `before.mov`, `after.mov` (two Split Right each) and
  `compare.png` (frames 50 ms apart: before, the card slides in empty and the list fades in by 0.3 s; after, the list
  slides in with the card).
- **Measurement note.** Between 20:45 and 22:35 my harness left its test apps running (an exact-pid check missed the
  `/private` prefix): those runs were dropped and run again.
- **For the user.** ⌘D and ⇧⌘D: the New Pane list should slide in with the card, as a browser card does. On a short
  card (several ⇧⌘D), ↑ to the last row keeps it in view.

### Track O (item 43)

- **What went.** 59,679 → 58,920 lines (−759) over the app, HerdrKit, the UI tests, scripts and plugins: dead
  defaults, parameters, inits and a `done` count no view read; 30 accessibility ids no test reads; one-caller generics
  (`AgentRow<Hover, Trailing>` is `ArchivedRow`, `Pill<S>`); copies merged (the scroll-edge fade, `PluginInstalls.ask`
  for three alerts, a plugin's version and busy line, eleven UI-test copies of a card's `layout.apply`, the text,
  side-pane, tab and clipboard helpers); about 560 comments that restated the code or told history, and broken design
  anchors. Dropped features left no code, only words (README, D45, D63, the plugin API's "Needs …" notes).
- **Splits.** Only types that stand alone: `DragSource`, `BrowserToolbar`, the placeholder script, the program asks,
  the UI tests' waits.
- **No pattern kills.** `make lint` rejects `pkill` and `killall` (a SwiftLint rule for Swift, a `git grep` for shell,
  Python, the Makefile and CI); the e2e helper and the follow test kill the pids `pgrep` found.
- **Kept.** `dropAgentsView` (agent pins, Settled, pinned tabs and old folds, all phase 57: users have them), the old
  trust.json and Markdown-mode reads (phase 55–56), and `ovvi:files`/`ovvi:diff` labels (they live in herdr sessions).
- **Review.** Four reviewers, 0 blockers, 0 should, 18 nits; 13 fixed, 5 optional shrinks left (one place for the
  lint rule, a pgrep-and-kill helper, small test-helper moves). One auditor removed `HostStore.needsYou`, which the
  Dock badge reads: the build caught it and it stayed.
- **Runs.** The UI tests the batches touch, 125 in four chosen-test runs: 42580993371 (30, one red),
  42581000344 (32), 42584948783 (32), 42584952448 (32 with the red one) all green after one fix.
  `testACardWhoseFolderWentComesBackWithItsPlaceholder` read herdr's snapshot just after the helper started the
  server, before its socket was there, and the throw ended its wait: it waits out a missing socket now. GitHub's
  release downloads gave 504s for an hour, so three runs ran again with no change.

## Round 6 (items 51–59)

51. "with archived sessions, let's not show border whenits collaped, show border only when its expanded, and when
    expanded currently it flickers while the sessions are loading, let's make sure we show loader, load everything and
    then display avoid flickers, i am seeing this more in remote sessions, when archived sessions is opened, cursor
    should be activated on search input" (Track B).
52. "on tab hover with plugins in it, it shows cat command as the tui placeholder is basically cat, but we we should
    show correct plugin details on the hover, don't show cat or terminal ones for plugin panes" (Track B).
53. "so the bottom padding adjustments we did right, they look good, and can be applied to even in non floating panel
    view as well, only the top paddings are flaoting panel specific ones" (Track E).
54. "when cm+n is pressed the new view is much better, however, those sessions load in split seconds, so the sessions
    kinda flicker, can we fix that flicker? improve session loading, either cache things or may be make it faster so it
    doesn't flicker" (Track A).
55. "for the dots indicating the sessions in sidebar, let's make the background gradient, like after archived sessions
    we should see the gradient like thing making its background transparent, so the dots blend well if that makes
    sense." (Track B).
56. "cmd+k is still very laggy man, can we improve and make it more snappy, what makes it very slow? its just a list
    right? understand the core issue better and improve it" (Track K).
57. "stress test the sidebar with multiple sessions and one sessions with way too many workspaces and agents, in order
    of 100s, i see sidebar swipe and scroll is getting laggy in that order, can we virtualise the list when the sidebar
    list gets long and optimse its performance overall? figure out what's the best way to improve it" (Track U, new).
58. "i don't like any of your landing page mockups, let's do one thing, let's not focus on landing pages for now, come
    up with research on marketing view of this product like how we sell this to users, we shouldn't ideally focus on
    herdr for our app. goal is more of tui + gui thing, with custom plugins that can be controlled by agents or humans,
    and sessions persists, like you can even connect from any device and all restore as expected, we should focus on
    remote connections, idk, think through all features our app provides, give me multiple views on how we should put
    our story or show where we are different and better" (Track V, new, report only).
59. "in the cmd+n window add machine should open add machine section within settings window, do not open the overlay
    one" (Track A).

### Track B, round 6 (items 51, 52, 55)

- **Cause (51).** Each agent's first page landed in the list as it came, with the empty state's line between, and
  the loader waited 0.3 s on its own: on a slow remote the shelf grew in steps. The border drew while folded too.
- **Fix (51).** The shelf reads every agent's first page, then shows them together; the first time a loader
  ("Reading sessions…", after 0.3 s) stands in the list's place, later opens show the machine's last list that read
  whole at once and swap in the new one when it comes. The next pages come in together too. The border shows only
  while open, and a click that opens it puts the caret in Search.
- **Fix (52).** A hover card's row for a plugin, a browser or New Pane names it and what it shows, as its card
  header does (File Explorer ovvi, Git ovvi, Browser example.com), never its placeholder's `cat`; terminals and
  agents are as before.
- **Fix (55).** The dots lie over the pages' foot: the list has 18 pt more room at its end (its last row still
  ends 11 pt above the dots) and, while rows lie under its end, fades over 36 pt, so rows thin out behind the dots
  in Glass and Classic alike. A mask, not a painted gradient: Glass's sidebar is a blur, which a color would band.
- **Measured** (2x pictures): folded, no border lines (before: 2 px = 1 pt at y 2004 and 2062); open, the border at
  y 1416 and 2062; at the list's end the last row 22 px = 11 pt above the dots, as before.
- **Review.** Six should-fix items (a first-frame "No closed sessions" flash, a next page over the fresh list, a
  failed read cached, the loader inside the lazy stack, the focus timing, the fade's docs) and four nits, fixed.
- **Runs.** CI 42595067474: 12 of 13 chosen tests green (Archived, hover card, dots, swipes, scroll into view); the new
  plugin row test made its card in beta without showing beta first, fixed. CI 42596360702: it and two more, 3
  executed, green.
- **Pictures**, before and after, dark and light: `~/Downloads/ovvi-research/p57b/r6/index.html`.
- **For the user.** On a remote machine, open Archived Sessions twice: a loader, then the whole list at once; the
  second time the list at once. Hover a tab with File Explorer, Git and a browser. With two sessions, scroll a long
  list: the rows fade out behind the dots.

### Track V (item 58, report only)

- Report: `~/Downloads/ovvi-research/marketing-story.html`, one self-contained file with the pictures inlined. No app
  code changed. Sections: the app's features in six user-facing groups plus the gaps, personas, a comparison of 14
  products with sources, seven positioning angles (each with promise, proof, a 30 s shot list, what it says no to,
  risks and a score), banned words and feature names in user terms, the recommended story, three headline pairs, a
  3 min walkthrough outline, and open questions.
- Recommendation: “Where the work lives”. Remote machines and persistence are the cover (“Your terminal, wherever
  your code runs.”). TUI + GUI, agents driving cards and plugins are the three chapters inside. herdr is credited
  only in How it works and the FAQ.
- Findings: the closest rivals are Tern (Stencil: blocks, daemon-owned sessions, remote over QUIC, Luau plugins,
  closed beta) and Rex (Superlogical: durable sessions, real login on remotes, terminals only so far, free). Claude
  desktop now has SSH sessions with chat, diff, terminal and browser panes. Cursor's remote agent stops on sleep,
  and Zed's agent stops when the client disconnects; both are proof for the persistence angle.
- Gaps the story must not hide: no iPhone app yet (say “any Mac”), plugins install per Mac, agents can't drive a
  browser page yet, no team sharing, and herdr (plus Perl for the relay) must be on each machine.
- Pictures: reused Track Q's captures from `ovvi-dev-p57q` (`landing/assets/`) and a crop of Track R's New Pane
  chooser that leaves out the shell prompt. No new GUI runs.

### Track U (item 57)

- **Measured.** Release builds of main and the branch, by turns, on throwaway sessions: one of 200 spaces and 300
  agent panes (stand-ins: `pane.report_agent` from outside, three agents a second changing state), two of 10. Posted
  trackpad events (fast scrolls of 30 × 60 pt with momentum, two-finger swipes to the next page and back, a fold, two
  pointer sweeps), `-recordLatency` frame records, `sample`, a temporary count of the rows made. "With an AX client":
  a process that reads the app's whole accessibility tree every second, as XCUITest does. The Mac's load was 40–150.
- **Cause.** (1) An eager `VStack`: every update of the page made all 500 rows (1,400–1,800 a scroll), and a swipe
  that brings the page in made 2,300 in one frame. (2) `HostStore.groups` looked up each space's parent among all
  spaces: 40,000 observed reads at 200 spaces in every sidebar update and menu refresh. (3) A hover region in every
  row (`ChromeStyle`'s and the hover card's `onHover`): AppKit hit-tests each at every scroll frame, which cost half
  the frames once the list was lazy. (4) In the lazy stack, a 0.14 s fade of a row's hover fill kept the main thread
  busy for half of a pointer sweep, with 100 ms frames.
- **Fix.** A `LazyVStack`. The drop frames go to a non-observed box in the content's own space (a scroll moves no
  frame); a drop point adds the visible top; blocks not made lie above or below; a dragged row keeps its frame. The
  `ScrollPosition` is only asked. `WorkspaceRow` is `Equatable`. `groups` is one pass. One pointer for the list
  (`onContinuousHover`): each header and agent line reports its frame, the one under the pointer lights through its
  own observed `RowLight` (no row draws again), nothing lights while the list scrolls, and a target that moves under
  a still pointer finds it again. The sidebar's fill comes on with no fade.
- **Before → after**, per 1.7 s scroll (120 Hz: 200 frames), no AX client: 9–25 → 106–129 frames, p95 180–250 → 23–28
  ms, the main thread 1.6–1.8 → 0.9–1.1 s, rows made 1,400–1,800 → 73–122. With the AX client: 10–36 → 78–114
  frames, p95 220–280 → 33–53 ms. A swipe to the big page and back, the worst frame: 0.3–1.6 s → 0.10–0.14 s
  (with the AX client 0.36–5.0 s → 0.15–0.5 s). A fold's longest turn 0.5 s → 0.16 s. A pointer sweep: the main
  thread 1.5 → 0.3–0.8 s per 5 s, longest turn 8–15 → 9–48 ms. Records and recordings (before left, after right):
  `~/Downloads/ovvi-research/p57u/`.
- **Left.** Rows that come into view are made then: about 10 ms of the main thread each (SwiftUI's modifiers per
  row), so a fast scroll runs at 60–75 frames a second, not the display's 120. An AppKit table would reuse rows; the
  look, folds, drags and hover cards would all need building again in it, for the last part of the way.
- **Decisions.** The hover fill does not fade in the sidebar (the tab capsules keep theirs). The first-page check
  for the selected row asks the row's own id, then the fade's room, since a new page's first ask can be dropped.
- **Review.** No blocker; five should-fix items (the fade, a page made again, lights after a move, lights in a
  scroll, a dragged row's frame), the test's bound, and nits: fixed.
- **Runs.** CI 42606451106: 34 of 35 chosen tests green (sidebar, agents, hover cards, drags, swipes, the stress
  tests); `testTheSelectedRowScrollsIntoView` waited for a row out of view to exist, which a lazy list does not make.
  CI 42606461976 on an eager `VStack` tag: the new stress test red (a 20 s frame, 1,000 rows made in one swipe).
  CI 42609498951 on the fixed test: it and the stress test, 2 executed, green.
- **For the user.** In a session with hundreds of spaces: scroll fast, swipe to another session and back, fold a
  space, and rest the pointer on an agent row for its card.

### Track K, round 6 (item 56)

- **Measure.** A Release build on a session of the user's size (6 spaces, 30 tabs, 6 working agents, Archived Sessions
  open), XCUITest attached as the accessibility client, keys posted inside the app, Time Profiler and lldb. The Mac's
  load was 50–80.
- **Cause.** The list was all of a key's time: with the rows not drawn at all every key took 7–17 ms and ⌘K 19–23 ms;
  with them the first letter took 136–173 ms. Two parts. SwiftUI rows in the window's graph: each new or changed row's
  accessibility made SwiftUI walk all the window's focusable views, and the lazy stack diffed and placed every row.
  And each keycap's live glass, which is a SwiftUI host of its own: AppKit rows with glass keycaps still took
  105–125 ms for the first letter, 25–46 ms with drawn ones. SwiftUI rows hosted in a table's cells were worse
  (40 ms for a one-row change): each hosting view is a graph of its own. Scoring is under 1 ms; no other view of the
  window runs a body per key (Latency's own record aside).
- **Fix.** The palette's rows are drawn by AppKit in a table that reuses the few row views in view (`RowTable`,
  `RowView`): the symbol or a tile (SwiftUI's `ProgramTile`, rendered once per icon), the texts, the pill and the
  keycaps, the keycaps' glass drawn. The other lists keep their SwiftUI rows (state icons, spinners, buttons, drops).
- **Numbers (warm, user's size, client attached).** ⌘K 69–86 → 15–18 ms (the first open of the app 64 ms); the first
  letter 136–173 → 25–28 ms; the other keys 12–195 → 14–47 ms (the longest, a list growing past the panel, 174–195 →
  23–47 ms). The stress session (30 spaces, 120 tabs, 40 working agents), after: ⌘K 27–49 ms, the first letter
  47–100 ms, the other keys 18–69 ms (round 2: 134–178 ms for the first letter).
- **Look.** Measured on 2× pictures against the SwiftUI rows, dark and light: rows, texts, tiles and pill in place;
  SwiftUI's hierarchical styles draw fuller on the glass than AppKit's label colors (white 100/40/27 % in dark, black
  100/42/31 % in light, measured), so the rows use those. Left: 1 px (0.5 pt) on some symbols and the keycaps' glyphs,
  and the drawn glass is close to, not the same as, live glass.
- **Review.** A pooled row kept its hover, headers and gaps lit the row, every update scrolled back to the light,
  the header sat inside the row's button for VoiceOver, Increase Contrast was lost, and new rows drew 2× tiles on a
  1× screen: all fixed before CI.
- **Runs.** CI 42609386222: 31 palette, panel, menu and stress tests green. CI's Debug build, XCUITest attached:
  testPanelsAndSwitchesReactAtOnce's first letter 172 → 32 ms and ⌫ 121 → 20 ms; the stress session's first letter
  372 → 56 ms and its slowest ⌫ 575 → 51 ms.
- **For the user.** With Raycast or another accessibility app running, open ⌘K and type: each key should draw at once.

## The phase's end

### Findings (finish)

- **Docs pass.** The tracks had written their pages. The pass removed what was left of the two sidebar views (a "sidebar
  view" in the window's state, the `agents` scene key), D111's pointer to a removed D109, the Agents row in the
  glossary and the `settleAfter` history; Features gained Install herdr, the ⌘N picker, ⌘/⌥ link underlines, HTML in
  the browser, Redraw Terminal, web cards that come back, chat times and ticks, and ⇧] ⇧[. Later checks for rounds
  3–6 (spaces, the notices, the new-window view, the sidebar, pinch, padding, libghostty, Classic, Ovvi Dev, the
  palette) found the pages current.
- **Final review** (0 blockers, 3 shoulds, 11 nits; the shoulds and five nits fixed): ⇧, ⌃ or ⌘ pressed over a
  terminal sent libghostty two made-up pointer moves (a program that tracks the mouse got motion reports); a ⌘N
  picker window that macOS restored opened `default` by itself; the fold check was written three times.
- **Cause, the space-row drag (CI, both full runs).** A busy app's `DragGesture` reports its first change after the
  pointer moved on, and the drag took that late point as the grab: the image sat off the pointer and the dragged
  row's middle fell short of the row it was let go on, so nothing moved. **Fix:** the grab is the gesture's
  `startLocation` (a lesson).
- **Cause, Archived's resume (CI).** A typed line wrapped at a space, and herdr's `pane.read` keeps no trailing space:
  `claude--resume`. Every read of a typed line now goes through `waitFor(_:toShow:)`, which compares without
  whitespace (a lesson). Pane ids can hold letters (`w2:pC`).
- **Stale tests.** The ⌘ keycap sat beside the tab's new pin, not its × (then the keycaps went in round 4). The agent
  start test skipped on every CI run, since CI's `claude` is the stand-in: it now skips only for a real one, and runs.
  The sidebar stress test's ⌃⌘1 found its space selected already, so the list did not scroll to it.
- **Not found.** One full run's shard hung from one test on: the runner never got the new app's pid, and every later
  test waited on its screen recording until the job limit, with no assertion failing (`testmanagerd`; ci.md). One
  palette scroll that never moved, and one stress-test ⌘D whose second card the accessibility query never counted
  (the app split, the recording shows it), each once; neither came back in eight full runs and two on-demand runs.

### Runs (finish)

- Red, each fixed before the next: p57-final (132467f2) full runs 42548068295 and 42548074923 (the space drag, the
  keycap, a palette scroll); p57-final2 (3c694fe2) full run 42554062143 (the runner's hang in shard 0) and on-demand
  42554074138 (the stress ⌘D); p57-final4 (c7a4de17) full runs 42611892909 and 42611901292 and on-demand 42611908811
  (the agent start's pane id, Archived's wrapped resume, the stress test's jump).
- Green on the way: full 42554068412 and on-demand 42548082531; full 42587591358 and 42587598516 and on-demand
  42587606624 on Track O's head (p57-final3, 20978ec8). Chosen tests 42546622667 (the review's fixes, 9 tests),
  42560943755 (the stress test), 42595679366 (the agent start, no longer skipped), 42619945111 (8 tests on the fixes).
- Green on p57-final5 (652da9ea), the final head: full run 42621495316 (Executed 55, 56, 56, 56 and 57 tests, 0
  failures; shard 4's artifact upload failed on a DNS error after its tests passed), full run 42621503671 (the same
  counts, 0 failures, no skips) and on-demand run 42621512673 (Executed 3, 5, 5 and 5 tests, 0 failures).
- `scripts/test-times.tsv` from full runs 42587598516, 42621495316 and 42621503671 and on-demand runs 42587606624 and
  42621512673.

### For the user

- Install a build of main (`make app`): File Explorer 1.10.14 and Git 1.10.5 replace your copies. A Debug build is now
  Ovvi Dev (its own settings and notifications).
- **Windows.** Launch, ⌘N and a Dock click with no window show the new-window view and connect to nothing; known
  sessions show at once; Add Machine… opens Settings ▸ Machines. Install herdr on a Mac or host without it.
- **Sidebar.** Spaces unfolded and bordered, their agents newest first, an untitled session's first prompt; fold one
  and relaunch. Archived Sessions: search, the agent menu in the field, a loader then the whole list (twice on
  devvm-aai), the dots over the fading rows. A session with hundreds of spaces: scroll, swipe, fold.
- **Terminal.** Hold ⌥ over a link with the pointer still: the underline as with ⌘; ⌥-drag still selects a rectangle.
  ⌘-click a deleted file's path: "File not found". ⌥⌘R redraws a garbled TUI (the `kq_dispatch` lines are Meta's
  launchers').
- **Cards.** An `.html` link opens in a browser card; a file card on HTML has Open in Browser. Leave a browser and a
  Rich Text card idle overnight; Force Quit an "Ovvi Web Content" process: they come back where they were. Pinch a
  browser page. A devvm-aai browser card after a sleep loads without closing the window.
- **Keys.** ⌃- ⇧⌃- Back and Forward in File Explorer and Git; ⇧] ⇧[ by file in a diff; ⌘A in a locked Source view;
  the Markdown pencil.
- **Agents.** Relaunch with Chat on Claude Code and Codex, also on a Mac without Meta's launchers; chat times and
  ticks; Settings ▸ New panes open.
- **Speed and look.** ⌘D and ⇧⌘D beside a busy agent (Glass and Classic); ⌘K's first letter and ⌫ with Raycast
  running; Classic dark's borders; floating panes' even top and bottom room.

## Round 7 (items 60–68)

60. "my browser and other plugins are kinda blank and stuck now ... i basically left the app open for quite some time
    and went and browsed different things ... its just even when i focus on them they are not restoring, i have to
    close the pane and open a fresh pane ... its not just browser btw, i see file explorer, git, basically all plugin
    panes are just stuck like blank" (Track W).
61. "archvied sessions not loading for remote machines, they are stuck at reading sessions forever, figure out and fix
    it" (Track B).
62. "cmd+d is still pretty jagged and its very off putting in terms of experience. figure out properly why the
    jaggedness, measure and profile where the heavy load when opening the pane, why can't it be fully smooth when
    opening panes" (Track J).
63. "before when ovvi is closed with multiple sessions or windows open, and i quit and open ovvi back, those windows
    with corresponding sessions will be opened. now that's gone after the recent change in cmd+n flow. this is how the
    flow should be, if no windows are previously opened, then open empty window saying connect to session, if
    previously user had some windows open, restore them, on normal cmd+n show the connect to session options"
    (Track A).
64. "remove the new space button on the sidebar, we already have new space button in the center. also show good empty
    state when no spaces are open. ... something simialr to what you worked in the onboarding flow, like we can show
    some repos to open, etc, show ovvi logo at top though, don't copy this exactly, but something like that"
    (`.build/fb57/r7-11.32.49.png`, `r7-12.19.26.png`; Track A).
65. "enable right click on sidebar, like right now if i right click on empty sidebar, nothing shows, probably we can
    show options like new space, detach session etc" (Track B).
66. "https://x.com/adilrc/status/2118715595633951190 - check this tweet, there is something about liquid glass
    improvement, see if we can improve that" (Track T).
67. "once all these are done invoke this skill https://github.com/caldoai/skills/blob/main/skills/untangle-codebase/SKILL.md
    and improve and clean" (Track O, after the rest of round 7).
    Follow-up to item 67: "wait we can actually do land all the cleanup, but merge to main as one commit, so its easier
    to revert. the comment cleanup is removal of comments right, not addition of comments? we should have few comments
    that mention only on some assumptions or implicit things which cannot be changed. no mention of old code, or old
    design etc, no backward compatibility shit, just the current code and clean, lets make sure we do run e2e and we are
    confident that this will not break anything, get things reviewed etc, and once we have confidence, let's merge it as
    one commit".
    Then: "yep no backward compat code at all, we don't have any users yet, and we don't need all our old design and
    compat code, cleanup all of that too". And, for a pass over the cleaned code: "Read this entire project and find
    everything that’s broken, inconsistent, inefficient, or no longer needed. Fix what you’re sure about and list the
    rest for me to review".
68. "let's also plan on onboarding flow ... start with very brief intro of what ovvi is, how it works etc, then start
    with empty pane and split panes, then show about tabs and then show spaces, basically incrementally adding things
    ... mention about agent integrations and chat view, and after that show the default plugins like file explorer,
    git and browser, and give overview on custom plugins, and then end with remote machines etc. ... on onboarding we
    open like a mini window like how many apps show onboarding, with minimal clean design, and text and screenshots
    overlayed with minimal animations ... less number of pages, but cover all things clearly, with of course a skip
    option. so update that same html report and replace that with five designs of this type of onboarding"
    (Track X, report only: `~/Downloads/ovvi-research/onboarding-plan.html`).

### Track W (item 60)

- **Cause.** WebKit gives up on a GPU process that stops answering and starts a new one, but its kill fails: xpc logs
  "Could not signal service com.apple.WebKit.GPU: 1: Operation not permitted" (the user's log has it 8 times between
  10:17 and 10:30). The old process lives on and keeps every page's drawing connection; once it answers again more
  than about 30 s after WebKit gave up, it answers no page, and no page reconnects. So every card, browser and
  plugin, stays blank, Reload too (it loads in the same page process); a new pane gets a new process and draws.
  Forced in a test build by stopping its GPU process (SIGSTOP) until WebKit gave up (9–25 s), 30 s more, then
  resuming it: the browser, Markdown and Explorer cards went blank and stayed blank, also after Reload. Killing that
  old process by hand brought all three back in place with no reload. `kill -9` alone never sticks: the pages see
  the process end and reconnect (Track D).
- **Fix.** Every 2 s while web cards exist, the app reads WebKit's GPU process id (`_gpuProcessIdentifier`, private:
  WebKit has no public word of its GPU process or a way to end it, and every public signal stays silent: no delegate
  call, the page still runs script and `requestAnimationFrame`). When WebKit drops a GPU process that still runs (same
  pid and start time), the app ends it. The pages reconnect to the new one and draw where they were, with their scroll
  and state (no reload); a kept card's paused page does so when it shows.
- **Decisions.** End the stale process rather than reload or remake each card: no state is lost and no page process
  is left behind. A timer rather than a check on focus or wake: a card the user looks at in a background window has
  neither. `takeSnapshot` fails on a stuck page (WKErrorDomain 1), but as a check it costs a picture of every card
  each time.
  The on-demand set: CI's virtual Mac has no GPU process (the test skips there).
- **Decisions (review).** Per card's pool, not over all of them: a pool reports 0 until its own pages draw, so a card
  that never drew while the only one that did closed must not read as a dropped process. Each end is logged
  (`dev.ovvi.app`, category `web`).
- **Runs.** testWebCardsDrawAgainAfterTheGPUProcessHangs, local: on the old code, with the process held 35 s more and
  let go, red at "the browser after Reload" (blank, 101 s); green on the new (53 and 62 s, at a load of 90–150), the
  end logged. CI 42703874300: Track D's two web recovery tests green, this one skipped (no GPU process). On CI's
  screen these pages showed blank from the start and the Git card listed no commit, so the test skips before any
  picture: 42695883792 and 42702303079 failed there on that.
- **For the user.** Leave Ovvi open with browser, Explorer, Markdown and Git cards (some in other tabs) while the Mac
  is busy. If a card still goes blank, wait a few seconds: it draws again by itself, and the other tabs' cards when
  shown; Reload works too. If one stays blank, tell us and send `log show --last 2h --style compact --predicate
  'process == "Ovvi" AND eventMessage CONTAINS "GPU"'` ("Ended the GPU process … WebKit gave up on" is the fix at
  work).

### Track X (item 68, report only)

- Report: `~/Downloads/ovvi-research/onboarding-plan.html`, one self-contained file (pictures inlined), replacing the five
  practice-window flows (the old file is `onboarding-src/onboarding-plan-v1.html`). No app code changed.
- Five designs of a small welcome window, each a clickable prototype in light and dark: A Picture book (7 pages, a ring
  per picture), B Building up (5 pages; frames of one window as it grows, words in a glass card), C Setup assistant (7
  steps in a sidebar, numbered marks), D Four cards (4 sliding pages of three pictures), E Spotlight tour (6 steps, a
  moving spotlight and callout). One set of words in the user's order; no herdr; spaces are always "spaces".
- **Decisions.** Recommended B (the incremental story in 5 pages), runner-up E (the tour the user liked in the first
  report). Estimates: A 11, B 14, C 12, D 11, E 14 agent hours, with a UI test that
  takes the pictures again and writes the marks' frames. A reviewer's two rounds fixed the welcome copy (no "close the lid"
  for This Mac), prototype bugs after Skip, marks off target and Reduce Motion.
- **Pictures.** Ovvi Dev of `9205ad6b` on `ovvi-dev-p57x-a`, in a herdr setup of its own (`XDG_CONFIG_HOME` in `/tmp`,
  which herdr and Ovvi's launchd start both honor), `-configFolder`, `-archivedHome`, a clean shell (`ZDOTDIR`). Layout
  through herdr's CLI and `ovvi` (`agent claude`, `open git|browser|explorer`, `plugins new`) run as a pane of that
  session with a clean environment; clicks posted only into that window under the GUI lock. Claude Code is the
  repository's stand-in with a scripted turn. Machines in the new-window view are made-up names on 192.0.2.x.
- **Found.** A separate `XDG_CONFIG_HOME` gives a throwaway herdr world where the new-window view lists only its own
  sessions (plus a stopped `default` row herdr always lists); a picture pipeline can use it for clean session names.
  The file card's Open With shows the Mac's default app for the file (a `.css` showed a competitor's app); pick files
  whose default is a system app for pictures.

### Track B, round 7 (items 61, 65)

- **Cause (61).** A page of 50 counted every session it looked at, the left-out ones too (Agent SDK runs, `codex
  exec` runs), and Claude Code's reader read each SDK run's 256 KB tail. On a machine full of runs each page held no
  row and said more, so the shelf read page after page under "Reading sessions…" with no row. Round 6's first list
  also waited for every agent, so one slow agent held all. Measured here: 3000 SDK runs took 61 pages (13 s) before
  the one real session showed; over SSH far longer. The user's devvm could not be reached (its sshd refuses a new
  session on their ControlMaster, and a new connection asks for interactive auth), so the cause is from the code and
  local runs; the reviewer found no likelier one and checked every read is bounded (relay start 10 s, `Exec` 10 s).
- **Fix (61).** A page holds 50 sessions with a prompt and looks at 2000 files at most (`ClosedSessions.files`);
  Claude Code's reader stops at an SDK run's first line. The first list shows once every agent's page came or 2 s
  after the first did; a slow agent comes in after it, under "Reading sessions…", a failed one is named ("Could not
  read Claude Code sessions on ‹machine›.") with Retry. The readers are `exec`'d, so a timed-out read leaves nothing
  running, and a run that exits non-zero throws (Retry, not "No closed sessions").
- **Fix (65).** A right-click on the page header or under the rows shows the session's menu: New Space, Open
  Session…, Show/Hide Archived Sessions, Detach Session (off on the last page; it takes the page out of the window
  and the herdr session keeps running). Ovvi has no Rename Session, so none. On the ScrollView itself: a background
  behind it never got the click.
- **Review.** One blocker (a straggler and a next page wrote whole values over each other), three should (`more` on
  a store's end, readers not exec'd, exit status ignored), nine nits, fixed; then one should (a wall-clock check in the
  new test, now an order check), fixed.
- **Runs.** CI 42705568583: 15 chosen tests green (Archived, the remote stuck agent over the relay, the session menu,
  Detach, row and tab drags, swipes).
- **Pictures**, before and after, dark and light: `~/Downloads/ovvi-research/p57b/r7/index.html`.
- **For the user.** Open Archived Sessions on devvm-aai: rows within about 2 s, the rest come in. Right-click the
  sidebar under the spaces.
69. "can we have a splash screen or something on the first start of app, like right now when ovvi is started for the
    first time, it shows some blank window with no liquid glass effect or anything and then it flickers and changes to
    our app. can we make that smoother, may be we can use splashscreen showing our logo or something while the window
    is getting loaded, but we shouldn't show this for consecutive windows later, only on the first start. can we do
    that?" (Track A).
70. "in the sidebar can we add sorting button beside the + icon, and have two options like manual vs recently active
    or something like that, basically default is manual sorting, and the workspaces which has recent agent activity,
    that will be moved up in other sorting if that makes sense, basically if there is a workspace with one agent and
    its at the bottom and then that agent is finished then that workspace should be moved up coz it has recent agent
    activity, come up with better shorter name for this sorting, so we will have two options of manual vs recent
    activity one and also within a workspace, always sort the agents based on their tab positions, if in same tab then
    based on pane positions, basically fixed sorting withing workspace and you cannot change that, i think right now
    its sorted based on activity i guess, let's change that" (Track B).
    Follow-up: "in recent, leaving should just remove the done status but that shouldn't move the sorting, even after
    leaving, done to idle is not considered as change of status" and "disable dragging a row while in recent mode".

### Track J, round 7 (item 62)

- **Cause.** A split's slide ran on the main thread: SwiftUI laid out the resizing cards at every frame, so anything
  else the main thread did in those 130 ms dropped frames. That was the split's own turn (the stand-in card and its
  chooser, 20–60 ms), herdr's answer (snapshot apply, the new card's terminal surface, menus: 30–60 ms), the old
  card's web views, and other apps' load. Rounds 2 and 5 trimmed that work and moved it out of the slide, but any
  stall still showed. Instruments on the realistic session (Release, a shell with 20 000 lines of scrollback beside a
  browser and File Explorer, four tabs visited) had main with one 42–71 ms hitch and 5–9 one-frame hitches in
  each split's first 0.35 s, for ⌘D and ⇧⌘D on the terminal and on File Explorer alike. libghostty (the new
  surface, its Metal layer), the PTY resize and web views were not resized per frame: they already held their size
  until the slide ended.
- **Fix.** Core Animation moves the cards. Each card is its own hosting view (`CardMotion`): its frame takes its new
  place at once, and an animation of its layer goes from the old place in the render server, clipped (10 pt,
  continuous) with the card's edge drawn by the layer. The card keeps the larger of its two sizes until it lands,
  then lays out once. A stall on the main thread no longer reaches the slide. The sidebar's slide and window
  resizes still size the cards at every step. Under Reduce Motion nothing moves.
- **Runs.** A probe with an 80 ms main-thread stall mid-slide: SwiftUI's slide froze for about 75 ms and jumped
  (60 fps capture: 298 → 414, four frames still, → 589); Core Animation's kept even 16.7 ms steps
  (346, 403, 453, 497, 537, 566, 588). The motion test now checks each card's edges halfway through its slide
  against its old and new places: red on the first version (a vertical motion the wrong way: "split down: the
  top edge at -193", run 42721181130), green after (42721187078). A wide chosen set (dividers, drops, context menus,
  zoom, keys, float, kept cards, web drags; 42719328846) passed.
- **Runs, the realistic session after the change** (Instruments' hitches of the app's frames, the same 1180 × 760
  window, before and after in turns, 6 splits each: ⌘D and ⇧⌘D on the terminal, then on File Explorer). Hitches
  in each split's first 0.35 s: 54 → 44, the worst 33–63 ms → 42–63 ms. Nearly every one is marked "expensive
  GPU work": this Mac's GPU ran at 60–70 % with Ovvi idle (other agents' apps), and a moving card is composited
  again over Glass's blurs at each frame. The ones also marked "expensive app update" (the main thread's commits)
  went 19 → 9, most of those left at the split's first frame, where its own turn builds the new card. So the main
  thread no longer reaches the slide, and what is left here is the render server's GPU time.
- **Pictures.** `~/Downloads/ovvi-research/p57j/r7/`: `split-dark-before-after-8x.mp4` and
  `split-light-before-after-8x.mp4` (⌘D on the terminal beside a browser and File Explorer, before on the left,
  after on the right, 8 times slower; a 30 fps capture, all this busy Mac's capture gave) and
  `split-dark-frames.png`, `split-light-frames.png` (frames of the same, before on top).
- **For the user.** ⌘D and ⇧⌘D, on a terminal and on File Explorer, while an agent works: the slide should not
  stutter. (Since item 79 the light Glass shadow stays through the slide.) If a slide still
  stutters in Glass but not in Classic, it is the GPU's blur work, a look decision.

### Track B, round 7 (item 70)

- **Sort Spaces.** A menu beside the header's `+` (28 pt, 8 pt before it), a check on the current order, one app
  setting kept in the sidebar's defaults (`spaceOrder`): **Manual** (default, herdr's order) or **Recent**: the
  space whose agent changed state last first, by herdr's `state_change_seq`, which is one counter for the session
  (checked: three agents' reports gave 1, 2, 3, 4 across spaces). Not the app's `since`: a look at a finish (Done →
  Idle) changes that and must not move a space. "Recent", not "Activity": the shortest word for what moves a space up.
- **Recent's rules.** Under the pointer the order holds still and settles 1 s after it leaves (as the agents did).
  No reorder in Recent: a dropped row stays and Move Up and Move Down are off, as while the filter hides rows; no
  switch back to Manual by drag (the user's follow-up). ⌃⌘[ ], ⌃⌘1–9, the overview and the palette keep herdr's
  order.
- **Agents in a space.** Fixed: by tab, then by place in the tab's layout (left and top first), never by state.
- **Tests.** testAWorkspaceUnfoldsToItsAgentsByTabAndPlace (old code: newest change first) and
  testRecentPutsTheSpaceWhoseAgentChangedLastFirst (a finish moves its space up, held under the pointer, a look moves
  nothing, a drag of a third space to the top leaves herdr's order, Move Up and Down off, Manual again).
- **Review.** Two test blockers (a drag and a Move Up check that could not fail), two should (docs that said "the
  sidebar's order" for herdr's), nits, fixed.
- **Runs.** CI 42726632924: 10 chosen tests green (both sidebar agent tests, row and tab drags, swipes, the session
  menu, the dots).
- **Pictures**, dark and light: `~/Downloads/ovvi-research/p57b/r7/index.html` (Sort Spaces).

### Track T, round 7 (item 66)

- **Audit.** The one large, always-on Liquid Glass was a full-window `glassEffect` in the dark Glass window's
  background, under a black shade, over the behind-window blur (`NSVisualEffectView`, `hudWindow`, always active).
  The rest is small or short-lived and stays: the selected tab and space row, buttons, keycaps, the chat's reply box,
  question card and scroll buttons, and the panels (palette, popovers, hover card, notices, find bar).
- **Measured.** GPU time per process from `ioreg` (IOAccelerator `accumulatedGPUTime`), WindowServer and Ovvi, one
  Release Ovvi whose background switched live between variants in turns, so the rest of the screen's noise fell on
  each alike. With a terminal scrolling in the focused window: 598 → 468 ms of WindowServer GPU per second (three runs:
  −148, −125, −130); idle 53 → 34; unfocused about equal (the glass goes inactive there). Ovvi's own GPU time hardly
  moves (13–16 ms/s scrolling): the glass costs in WindowServer. The selected pills as glass or as a material: no
  measurable difference.
- **Fix.** No glass layer and no shade: the dark tint is one plain color, `#1d1d1d` at 0.845, the same linear map of
  the blurred desktop as the old chain without its glass. Over a dark desktop and over a white window with black text
  under Ovvi, every sampled pixel is within 1–2 levels of before (0.2 % of pixels differ by more than 1.5 %), and the
  white window still shows only as a soft light. An inactive window now looks exactly like the active one (before, it
  darkened by 2 levels). `glassShade` is gone.
- **WebKit (Track W).** The glass took about 13 % of the GPU's time while a terminal scrolled, in WindowServer. That
  adds to GPU contention under load, but it is not a likely cause of WebKit's GPU process stopping to answer.
- **Review.** No blockers; three wording fixes (the docs' ratio, a history comment, a test's doc comment), done.
- **Runs.** CI 42728932856: the six look tests and the Glass dark scenes, 7 executed, green.
- **Pictures**, before and after, Glass and Classic, dark and light, focused and unfocused, with the GPU tables:
  `~/Downloads/ovvi-research/p57t/r7/index.html`.
- **For the user.** Dark Glass over a colorful wallpaper (not measured: Liquid Glass lifted saturation a little, the
  plain tint does not), and the window's top edge (the glass layer drew a 1 px rim there, now gone).
71. "let's remove git projects section below the empty session one which we added, let's show the current open
    folder, new space and the logo and text, let's just remove git projects part" (Track A).
72. "sorting button is too big, it should be closer to + button and of similar size, align it well" (Track B).
73. "in archive sessoins, when i search for something not available, instead of showing no sessions found, it
    continuously shows reading sessions loader, we should show no sessions found, if no matches to the search, and
    also on esc on archives sessions search should collapse it and focus the current pane" (Track B).
    Then: "i don't like the search older sessions button, why can't we do it automatically, i saw agent automation when
    testing".
74. "let's also slightly increase space between session header and the first workspace in the sidebar, not too much
    increase, slight increase should be good" (Track B).
75. "in archive sessions, can we keep fixed height? i see the height of the archive sessions keep changing, when
    loader is there, when error message is there or when sessions are shown, let's fix it to one height, and loader and
    error messages should be vertically aligned" (Track B).

### Track B, round 7 (items 72–75)

- **72.** Sort Spaces' glyph is 11 pt semibold, 26×21 px, as tall as the `+`'s (21×21; before 30×25), and the two
  28 pt buttons touch: glyphs 33 px apart (before 47 px, frames 8 pt apart). Both on the title's middle (y 116–136).
- **73, cause.** With a search, the list's end stayed in view and read page after page, and the status showed the
  loader whenever pages were left, even between reads: a search with no match read the whole store under "Reading
  sessions…", long on a big remote store.
- **73, fix.** A search reads the older pages by itself, 0.3 s after the last key, one after another, until every
  store was read or the list holds 1000 sessions; a new query, another agent or a fold stops it (a read in flight
  runs on in its own task: a cancel would mark the agent failed). "Searching older sessions…" while it reads, then
  "No sessions found." or "No matches in the last ‹count› sessions.". No button (the user's follow-up). Paging, not
  a grep on the machine: on 50 transcripts of 10 MB `grep -rliF` took 8.9 s, a reader page 0.19 s (grep reads whole
  files, the reader the first lines and the last 256 KB). Esc folds the shelf, which empties the search, and gives
  the keyboard to the pane in view.
- **74.** The first row 4 pt further down: its top 33 px under the title's baseline (before 25 px).
- **75.** The open shelf's list is one height, 256 pt (five rows), whatever it shows; the loader, empty states and
  failures sit in its middle. The shelf's top stays at y 1416 (window px) under the loader, rows, the searching
  line and no match; before it sat at y 1848 under the loader.
- **Tests.** testArchivedSearchSaysWhenNothingMatchesAndEscReturnsToThePane (new); the stuck-agent and remote tests
  check the header holds still from the loader through rows to the failure; testRecent… checks the sort button's
  size, place and middle; testTheSelectedRowScrollsIntoView follows the 7 pt.
- **Review.** Five rounds: Esc broke the filter test (fixed), the search kept on a fold, a stale task id (another
  agent), the loader's identity switching, a loop that ended while an agent was still on its first page, and the
  cancel that marked agents failed; all fixed.
- **Runs.** CI 42749499750: 10 chosen tests green (Archived search, stuck agent here and over the relay, filters,
  pages, dots, Recent, scroll into view, untitled agent, the session menu).
- **Pictures**, before and after, dark and light: `~/Downloads/ovvi-research/p57b/r7b/index.html`.
76. "so we also have this report: file:///Users/hkandala/Downloads/ovvi-research/state-machines.html, let's address the
    8 bugs identified in it if they are still relevant, and also any minor fixes that have good impact but minimal
    changes, let's do fix all of them. provide this to cleanup agent itself, so it can work on it with its subagents,
    along with cleanups, all previous cleanup things still apply, don't take that report as ground truth, analyse and
    only if certain bug is valid and needs a fix we should do it. once all these are done, we make sure everything do,
    do one last check if codebase is all clean, then make sure all ci runs pass with no flaky tests and merge
    everything in one commit" (Track O).
77. "i just noticed chat ui when agent was testing and it looks yuck, why there is so much padding on message bubbles?
    let's also move the date and tick marks outside message similar to this: ... this is screenshot from imessage make
    it similar to this, no need of that pointy bubbles, our regular bubble is fine, just use similar padding like here,
    and move the timestamp and tick marks to below message similar to "Read Wednesday" part in that screenshot"
    (`.build/fb57/r7-12.09.08.png`; Track I). Then: "actually you know what, let's drop the timestamp and tick marks
    thing in messages for now, just bubbles should be enough".
78. "can we also invoke another agent to work on onboarding flow, from the previous report: onboarding-plan.html, i
    like the first one the picture book version itself, however, screenshots should be better and should be of better
    quality, content can be improved etc. so let's invoke this agent, and ask it to work on the onboarding flow
    following the picture book version and implement it, however it should implement five variations of it, it should
    invoke another 5 agents that work on different variations, different screenshot styles, different content,
    different flow as well, we would need to cover these topics panes, tabs, spaces etc but it can be structured in a
    better way may be, so try out and implement five variations and dont' merge them to main, but give me one final
    html report with full video recordings of each implemented onboarding flow. i will decide which version to merge
    and any changes needed etc" (Track Y; branches only, nothing on main).
    Follow-up to item 78: "also in settins somwhere there should be option to open onboarding flow, so user can open
    anytime again, and also for me to test, on first install and opne onboarding flow should be shown, also one more
    thing within onboarding flow we should set up and install herdr if its not isntalled, if herdr is installed on the
    user device we don't need to show that part in onboarding. so yeah on first launch we show, and once done or
    skipped we mark it and won't show it again, and can be accessed only from the settings".
    And: "the onboarding panel should use some floating panel kinda thing and not the ones with traffic light buttons".
    And: "also explore in different variations to have some beautiful animations of our logo and show the app name and
    logo first and then fade in to onobarding flow something like that? basically it should look highly polished and
    well crafted onboarding flow with unique but minimal and modern animations".
    And: "we should increase teh onboarding sheet should be bigger so its visisble well, take very high quality
    screenshots, zoom within screenshots when explaining in the flow, screenshots should take both in dark mode and
    light mode, and onboaridng uses relevant screenshots based on which mode it opens in".
    And: "also in that throwaway session, show many spaces with different agents running, like claude, codex, pi etc,
    and show many tabs, with different plugins, some screenshots should show combination of agent + browser or file
    explorer or git plugins, idk i am just giving random ideas, take different screenshots covering real time use case,
    also for chat view, avoid the permission prompt one, i see we are always taking one with permission prompt, show a
    real looking agent chat, with multiple tool calls etc".
79. "cmd+d split is now bit weird in terms of glass effect, like i see glass effect flickers on both panes when split
    happens, this wasn't a problem before, may be the liquid glass fix we did caused this issue? verify and fix this,
    there shouldn't be any flicker in liquid glass pane borders when splitting is happening" (Track J).
80. "chat bubbles padding is still not right, especially when long markdown messages are there, with long markdown
    messages spacing seems very less, i provided image of imessage chat, replicate those spacing for both single line
    and multiline markdown messages" (`.build/fb57/r7-3.12.26.png`; Track I).
81. "let's always default our app to open in dark mode for now, our light mode is still not great, so let's default it
    to dark, user can still change it to auto or light mode from settings" (Track T).
82. "when i run commands like claude update, or codex update, ovvi recognises those as agent sessions and show progress
    and shows them in sidebar, can we improve the detection, and detect only when agent is running? not other helper
    commands, if this detection is coming from herdr itself, don't workaround things, we can leave it, if we are doing
    the detection from our code, then let's improve it, figure out how herdr detects agent sessions we can do something
    similar" (Track G).

### Track J, item 79

- **Cause.** Round 7's slide, not Track T's dark background. While a card moved, `CardMotion` clipped the whole card
  (10 pt, continuous) and drew its edge as the layer's border. That made CardSurface's rims (plusLighter), its edge
  drawn outside the shape and the light Glass shadow one masked group, which rendered them differently until landing,
  where the SwiftUI surface came back: on every moving card. A window-only capture of ⌘D (light Glass) had the
  cards' still left and top edges in an in-between look for about 145 ms, then a jump of 9–11 levels at landing;
  the top rim read 253 before and 250 during.
- **Fix.** `CardChrome` draws a page card's surface as Core Animation layers (fill, keyboard fill, the plusLighter
  rim group with its top line and glow, the outside edge, the light shadow cut out under the card), behind the card's
  hosting view, animated with it: the render server draws it at each frame's size, never clipped, at rest and in
  motion alike, so nothing swaps at landing. Only the content is clipped, and only while the size changes. The
  page's PaneCard keeps its element and menus on a clear shape; the floating window and Overview keep CardSurface.
- **Match.** A probe app beside SwiftUI's CardSurface: sides and edges equal to the pixel, dark and light; the light
  top rim's band within 7/255, one light corner pixel by 22 (dark within 4). Every page card uses the chrome, so
  this shows only between a page card and the same card floated or in Overview.
- **Review.** One blocker: the chrome's space was flipped twice, so its surface grew from the card's bottom while a
  height changed (⇧⌘D, zoom, a close in a column); fixed, and the motion test now checks the surface's place mid-slide
  against the card's. Shoulds (placing it on resizes, dead branches, docs) and nits fixed.
- **Runs.** Red, the doubled flip with the new check: "split down: the surface's top edge -168 vs 77" (42877175587).
  Green: 14 chosen tests (42877182092); the head: see below.
- **Not fixed.** The lit card's 1 pt border is still drawn in its content: on a close that grows a lit card, its far
  side is clipped until it lands.
- **For the user.** ⌘D and ⇧⌘D in Glass, dark and light, and a zoom: the edges, rims and the light shadow should look
  the same before, during and after the slide. Not checked by a recording of the final build: the GUI was the user's.

### Track T, item 81

- **Found.** The app already opens in Dark when the setting was never chosen: `appearance` defaults to Dark
  (`AppSettings`), as it has since the setting was added, and D44, Settings and Theme and accessibility say so. Nothing
  else reads the key with another fallback or writes it at launch; the tiles, the View menu and the palette write it
  only on a pick. No test assumes Auto. No code change.
- **Why the user saw Auto.** The installed app's defaults (`dev.ovvi.app`) hold `appearance = auto`, from a pick in
  that app (the UI tests run the Debug build, `dev.ovvi.app.debug`, which holds Dark). A pick is kept, so it stays
  Auto until the user picks Dark (or, with the app quit, `defaults delete dev.ovvi.app appearance`).
- **Launch.** No light flash: on CI's Mac, which is in Light, the recording of a dark launch goes from the desktop
  straight to the dark window (gray 17 → 40–47, no light frame at about 17 fps). Not covered: a launch that restores
  windows (the tests ignore saved state).
- **Onboarding** is not on main yet: its first window must open after the app's appearance is set (Track Y).
- **Pictures.** Launch frames and recordings: `~/Downloads/ovvi-research/p57t/r7b/index.html`.

### Track O, round 7 (items 67, 76)

- **What landed.** One commit, `refactor: untangle the codebase`: 60,588 → 55,584 lines (−5,004), comment lines 7,641
  → 2,510. The untangle-codebase skill's audit (409 problems) became model code out of view files, `Window/` and
  `Sidebar/` feature folders, one owner for each defaults key, path, token, agent list and constant, HerdrKit's run
  helpers out of its client, shared test helpers and stand-ins. Comments stay only for facts the code cannot show.
- **Compatibility removed** (no users yet): the old sidebar keys' cleanup, trust.json's old shape, the old float and
  copy tokens (and migration.mdx), the old label words (`ovvi:files`, `ovvi:diff`, file/preview/markdown kinds),
  Markdown's old modes, manifest `permissions`, the API's `@since` history, `ovvi card`'s old `chat` field.
- **Bugs fixed, each with a test red on the old code:** a moved card's terminal or web view taken by a hidden page's
  late host (blank card: the full-run flake of `testMoveToTabLandsBesideTheLastCard`); a close with no question
  dismissing another close's dialog; a closed find bar's late read scrolling herdr's viewport; Find on a chat card;
  a write clearing every notice, and a notice's 4 s holding its caller; Start's reason lost after 4 s and no Starting
  progress; New Tab while a session is not live; a failed stream retrying up to 4×/s and blinking under
  Reconnecting; the browser's stale error over a prompt, Reload off after a failed first load, the remote alias lost
  by Not Now; a plugin toast that never settled after a failed Reload Plugin or a page reload; sh quoting of a `'`
  with a combining mark; a browser state write after its pane closed or over a newer one; macOS auto-correct in the
  explorer's find fields; the sidebar's scroll ask landing before its lazy row was built.
- **State-machine report.** Of its 8 P1s, 7 were real and fixed by cause (no Phase or Halt enums: each fix is a guard
  or one owned field); CH-1 was already covered by Track G's round 5. Triage:
  `~/Downloads/ovvi-research/p57o/r7/state-machines-triage.md`.
- **Decisions.** `make lint`'s grep is the one pattern-kill check (the pre-commit hook no longer has it). The
  future-work pages stay (plans, not old designs). `-forceMotion` turns on every motion (test only).
- **For the user.** `~/Downloads/ovvi-research/p57o/r7/for-the-user.md` (about 50 one-line items found and not
  fixed); report `~/Downloads/ovvi-research/p57o/r7/report.md`. By hand: move a pane and a browser card to another
  tab; drop a remote link while a card streams; Start a stopped session.

### Track Y (item 78 and its follow-ups; branches only)

- **Report:** `~/Downloads/ovvi-research/onboarding-variants.html` (films and stills beside it in
  `onboarding-variants/v1..v5/`). Five built flows on `onboarding-v1`…`onboarding-v5` (heads 1838a89c, 408a4ad7,
  eb4b5661, 61124c14, edd890cb), all on `onboarding-base` (616b8856, on abaa0c97): v1 Crisp picture book (7 pages),
  v2 Close-ups (4), v3 Annotated (6), v4 Living pictures (5, looping clips), v5 Building up (5). Recommended v5 with
  its page 4 split in two; runner-up v3. Nothing on main.
- **Base (shared by all five).** A borderless floating NSPanel (no title bar or traffic lights), 960 × 640 pt in the
  middle of the screen, scaled down only on a small screen; shown on the first launch, marked done by Get Started,
  Skip or Esc (`welcomeDone`); again only from Settings ▸ General ▸ Welcome to Ovvi (searchable); a herdr step only
  without herdr, reusing `HerdrInstall` (its `session` became optional), known before the panel opens so pages never
  shift; the menu bar's ⌘ keys do nothing behind it. It opens after the herdr lookup, so after the scene has set the
  app's appearance (Track T's note).
- **Pictures.** One shared scene, `scripts/welcome-scene.sh`: a private herdr world (`XDG_CONFIG_HOME`), five spaces,
  the four agents' stand-ins playing scripted turns with tool calls (no permission prompt), agent + Browser / Git /
  File Explorer, a custom plugin, made-up machines, home shown as `~`. Every variant shot both looks from it at 2x.
- **Films.** The e2e helper's `record`/`record-stop` with `scripts/record-window.swift`: ScreenCaptureKit films only
  the panel's rect, drawing only windows the app makes after the start. Found on the way: a borderless panel's
  title is not always in SCWindow (find it by level); top-level `await` on the SCK calls took the handler forms (no
  wait); `config.backgroundColor` is not retained (crash); a menu window in the exclusion list stops the stream once
  it closes; XCUITest's accessibility snapshots hold the app ~0.2 s each, which shows as bursts in a film.
- **Found (lessons).** xctrace leaves its raw `instruments*.ktrace` in `$TMPDIR`, 12–26 GB each, and never removes
  it: 13 runs filled the disk twice (deleted). `xctrace --launch` by path started the user's installed `Ovvi.app`
  (same executable name) with test arguments; found and killed. A film helper that outlived its test kept filming
  (macOS's capture mark showed in later screenshots); the helper and recorder now end it. Eight agents polling the
  GUI lock at different rates starved the slower pollers for up to 2 h.
- **Runs.** CI chosen tests, green: v1 42830999466, v2 42856662812, v3 42862586613, v4 42875850824, v5 42825360245.
- **For the user.** `git checkout onboarding-v<n> && make run`, then `defaults delete dev.ovvi.app.debug
  welcomeDone` for a first launch, or Settings ▸ General ▸ Show Welcome. Whichever you pick: re-take its pictures and
  film on a quiet Mac (the films were taken under heavy load and stutter in places; the app measured smooth).
    Follow-up to item 78, v4 chosen: "i actually like v4 of all, let's improve that a bit - i like video clips than
    photos, but it does unnecessary zoom ins, which are not good, keep the video as is, no zoom ins needed - we should
    see traffic light buttons for the window we show i don't see that - each page shouldn't automatically move to next
    page, only on click it should move, and then videos should keep repeating if the user is on same page - for the
    agents view show first tui and clicking on chat switches to chat view and text should say more like seamlessly
    switch between tui or chat view when needed - give me different variations of text for each page that i can choose
    from - install herdr page can be better with some detail on why herdr, and once done, it should say you are all
    ready to go something like that - overall text below the videos needs improvements, so give me different variations
    of it , make sure all video recordings are of extremely high quality. let's scrap other version, work deep on this
    v4 with my inputs, and give me final html report with text variations and final video. once i approve the text and
    changes, then we can merge it".
    v4 text picks and changes: running Plain ("Your work keeps running" / "Terminals, agents and tools live in sessions.
    Close the window or quit Ovvi, and they keep going."); layout Plain ("Panes, tabs and spaces" / "Split a pane with
    ⌘D, open a tab with ⌘T, and keep each project in its own space."); agents Warm ("Work with agents your way" /
    "Watch an agent in its terminal, then switch to the chat when it suits you: the same agent, mid-task."); plugins
    Warm ("Everything you need, right there" / "Open Git, a browser or your files beside any pane. Need something else?
    Make a plugin in TypeScript."); machines Punchy ("Remote, without the hassle" / "Any machine you can ssh to: the
    same panes and agents, still running while your Mac sleeps."); herdr Plain ("One more thing: herdr" / "It keeps your
    sessions running in the background, so nothing stops when you close the window."); done Plain ("You're all set" /
    "Your sessions will keep running from here on. Get Started, and open a folder or a session."). "for the herdr,
    those three icons and message are not good, let's drop them and show herdr logo, with install button, we have
    reason anyway as text below. can we make the onboarding pane bit more cool, pane should fully be covered with
    video, and the text and the button should be at bottom on a overlay with a gradient shadow something like that,
    that make the video and text seem immersive. you can take over my gui lock and finish this entire onboarding flow".
    Follow-up to item 80: "for the chat i see we changed max width of both user and assistant messages, can we revert
    that, padding is fine, but the messages width is too small now" (Track I).
    And: "in the onboarding recordings, don't show custom claude code tui please, use real one, and also i see that
    shortlink website you are using is done very bad, can we make that website better and make it look clean and
    doesn't look like ai slop? also wait for things to be ready in each state, we shouldn't show loading stuff in our
    recordings, and make sure splits are clean without jagged animations, repeat until we get a good oen".
83. "when reconnecting, i see overlapping messages, fix it" (`.build/fb57/r7-12.39.54.png`: "The terminal stopped"
    with its ssh error and Retry drawn over "Reconnecting to vps…" and the same error; Track F).
84. "i am pretty much done with this split shit man, look at the video, now the split at the end it jumps like a spring
    effect. its very evident, every time i ask you to fix split issues, one thing gets fixed and other new issue comes
    up, wth, is the code messy right now in the way we handle splits? we would need to clean that shit if that's the
    case, idk why its so hard make a simple smooth split, fix this shit properly" (`.build/fb57/r7-split-1.23.54.mov`;
    Track Z, new).
    Onboarding, same message: "the shadow overlay at the bottom should be much more dark especially in light mode, i
    see overlapping thing coz the gradient is not strong enough - herdr logo looks bad, add a rounded square border to
    it, make it small - change the image or icon we are using for checkmark at the end when all done, that green cehck
    doesn't sit well with our app design - when app is opened for first time, no window should be opened, only
    onboarding pane should be opened and once it reached you'r are all done state then window should open or on skip -
    that split issue is very evident in the onboarding video as well, once the split fixes are done we should re
    record everything once again" (item 78, Track Y4).
    Onboarding, later: "the border radius of onboarding panes should be same as regular ovvi window, it is bit too
    curved now - and the shadow thing is too dark and big now, see the shadow should be of less height just covering
    the text and it should be gradient like blending with the the video. after these changes don't do re recording
    etc, just finish things and rebase it on master" (item 78, Track Y4).

### Track Z (item 84)

- **Cause.** Not a spring: a second slide. herdr's snapshots were held for 0.13 s from the key (`slid()`) and then
  applied together, right at landing. `Ahead` let herdr's tree replace the stand-in tree on "the first snapshot with
  its pane evened", so a snapshot read before the split's swap or balance moved every card to a stale place for an
  update and back: land, jump back about 30 pt, slide again (the user's recording, measured per frame; the same in an
  app-only film of main, `~/Downloads/ovvi-research/p57z/main-split-frames.png`). Each card's content also laid out
  again at landing (laid out at max(old, new) for the slide), and its terminal or page 150 ms later. Four parts moved
  cards (SwiftUI's two passes, Core Animation, herdr's late snapshot, the content's relayout); each round fixed one.
  The audit: `~/Downloads/ovvi-research/p57z/audit.md`.
- **Fix (one motion per card, its place known at the start).** herdr's tree takes over, after the write, only once it
  places every pane where the stand-in tree does (`SplitNode.places(like:renaming:)`, 32-bit ratios allowed), else
  at the second snapshot after the write. The hold is deleted (`Slide.swift`). A card going to the same place (within
  half a point) is never armed again. Content lays out once, at its final size, as the motion starts; a terminal or
  web view in a moving card fits then too (`SettlingHost`); drags, the sidebar and window resizes still settle. A new
  card is armed in `makeNSView`, in the same update as the others (`entering` deleted). The keyboard card's 1 pt
  border is a `CardChrome` layer, so it follows the card's edge (item 79's "Not fixed" is gone).
- **Proof.** `-recordMotion` gives each card's place per display frame. The on-demand
  `testSplitsMoveEachCardOnceToItsPlace` runs ⌘D, a third card, ⇧⌘D, Split Left and Up, zoom, restore, a divider drag
  and closes on a terminal, File Explorer and a browser, in Glass and Classic, dark and light, and fails a card whose
  edge goes back, passes its place, jumps more than the curve allows, moves after landing, moves twice, whose surface
  leaves it, whose content lays out again, or whose terminal fits after the slide.
- **Review.** One blocker (the hand-over could end a split before its write returned, so a stand-in closed at once
  could come back); fixed: only after the write. Shoulds fixed: sub-point re-arms from float32 ratios, the 1e-3
  tolerance (now 1e-5), the test hook's display link on a card that leaves, a third-card step and a fit-at-start check.
- **Runs.** Red on main: CI 42909338423 (the first version of the test: "split left: the left edge jumped 647 → 662 at
  230 ms", "the content laid out again"); locally, every look: 48 cards laid out again at landing and two cards that
  slid twice (browser ⇧⌘D to 557 pt, then 511 pt). Green locally on the fix in all four looks. An app-only film of main
  (Classic dark, ⌘D on File Explorer): the edge lands at 2012 px, the next frame is at 2096 px (42 pt back), then a
  second 0.13 s slide; on the fix it lands once and stays. The display rate (`testSplitsKeepTheDisplayRate`, local,
  main → fix, medians): hitches, worst gaps and the main thread's CPU moved within the run-to-run noise (CPU 211–331 →
  210–329 ms), so dropping the hold and fitting at the start cost nothing measurable. CI: 26 chosen tests (splits, quick
  splits and closes, dividers, drops, context menus, zoom, keys, float, kept cards, web drags) 42929763942: 24 green,
  the two motion tests failed only where CI's main thread sampled a slide's tail (now judged by the armed span);
  then 42933010318 on the head: the motion test, the layout motion test and the keys test green. A shadowed
  `active` (focus follows the mouse) that the first run found is fixed. Films and sheets: `~/Downloads/ovvi-research/p57z/`.
- **Not fixed.** A narrow chat card still wraps its messages 150 ms after its width changes, so after a split lands.
  A close made by another herdr client can be preceded by herdr's own ratio a hair off (2 pt seen once): the test lets
  an edge go back by up to 3 pt.
- **For the user.** ⌘D and ⇧⌘D on File Explorer, a terminal and a browser, Glass and Classic, dark and light: every card
  slides once and stops; nothing moves or re-lays out after it lands. The split card's header buttons and path field
  sit at their final place from the first frame while its edge slides in to meet them.
85. "can we make the sorting of spaces window specific, right now changing in one window changes in other windows as
    well, we can have in settings somewhere to keep the default workspaces sorting" (Track B).
86. "let's introduce pinning of workspaces, let's keep it simple, one can pin the workspace either from cmd+k or by right
    clicking on workspace, no need to show any pined icon, and unpin also from those two places, and in sidebar, we just
    keep pinned ones to the top all the time in the manual sorted position, and a line separator and then rest of
    agents, no need to say anywhere like pinned etc. and the pinned section should be unaffected from the sorting"
    (Track B).
    Then: "actually dragging to pinned group can be a way to pin as well".
    Then: "pinning spaces should have animation where space moves up similar to the animation we already have when
    changing sorting, i don't see that happening in the agent testing i noticed".
    Then: "this drag and drop animation of pinned ones shouldn't have any flicker, i see some flickers right now", and
    "i think its struggling to prevent flicker, may be its just overcomplicating code, like how we did for split
    animations etc, let's make the code simple and do the dragging straightforward with no flicker and stuff".
87. "i don't see relaunch with chat button in flaoting pnae, i see chat tui toggle button though when its enabled, we
    should make sure to show relaunch with chat even in floating pane" (Track G).

### Track B, round 7 (items 85, 86)

- **85.** Sort Spaces is the window's own: scene storage `spaceOrder` in the window's root, handed to the sidebar as
  an environment binding (every page of the window shares it). Empty is Settings ▸ Agents ▸ **Sort spaces** (Manual
  by default; in Settings search as "sort spaces", "order", "recent"), so a window follows Settings until its menu
  picks. Agents ▸ Sidebar, beside Show closed sessions: the page that already has the sidebar's setting. The old
  app-wide key is left behind (no migration).
- **86.** Pin Space / Unpin Space in a space row's menu (not on a worktree row: it goes with its repository) and the
  palette, on the space in view. Pinned spaces sit on top in herdr's order whatever the sort, then a 1 pt line on the
  middle of a 20 pt gap while unpinned ones follow; nothing says "pinned". Pins are the session's, as herdr's order
  is: lines "‹machine› ‹session› pinned ‹id›" in the sidebar's defaults, beside the folds. Every snapshot drops the
  pins of spaces it no longer has (herdr gives a new space an old id after a restart; checked by the reviewer).
- **Drag.** Above the line pins, under it unpins (Manual: at the drop's place, before the next of that group in
  herdr's order, which may lie anywhere; last of the pinned ones goes right after the last, not to herdr's end;
  Recent: where Recent puts it). Recent refuses a drag among the unpinned ones, keeps pins and the pinned group's
  order. With nothing pinned, a line stands over the gap above the list while a space is dragged, tinted while the
  pointer is within 8 pt of the list's top: the pointer cannot go above the list, so it decides there (checked by
  eye in a mid-drag frame of the test's recording). Move Up and Move Down stay within the row's group.
- **Order elsewhere.** ⌃⌘[ ], ⌃⌘1–9, the overview, Move Pane to Tab and the palette's places follow herdr's order
  with the pinned spaces first, the sidebar's in Manual; not Recent, which moves under the keys.
- **Flicker, cause and fix.** Frame by frame (30 fps from the test's recording): (1) the sidebar read pins through
  @AppStorage, a frame or more after the drop wrote them, so for about 200 ms the rows showed Ahead's new order with
  the old pins; now pins are one observable set on the session's store (`HostStore.pins`), written and shown in the
  drop's own call. (2) The slide math counted a 2 pt gap per row (from before rows were 10 pt apart) and not the
  line's 10 pt, so rows jumped 8–18 pt at the drop; now 10 pt, and the line's gap when a drop pins or unpins.
  (3) AppKit's drag loop draws no frame for 0.3–0.5 s after a drop (measured: performDrop to `endedAt`), so the
  0.22 s landing glide showed as a still frame and a jump; space rows no longer glide: the image goes and the row is
  in the gap the slide opened. A pin from the row's menu waits for the menu to close (its fade draws no frame
  either), then moves as a sort change does (0.2 s ease-out). The line hides while a space is dragged.
- **Measured** (2x px, 30 fps): menu pin, the row under moves 94 → 111 → 135 → 155 → 174 → 188 → 193 → 194; drag pin,
  the dropped row in its slot in the drop's frame, the others still; drag unpin, the slide 194 → 136 → 111 → 101 →
  95 → 94, the row in its gap at the drop. Frames: `~/Downloads/ovvi-research/p57b/r7c/frames/`.
- **Tests.** PinTests: testEachWindowKeepsItsOwnSpaceOrder (two windows, then Settings' default on a new launch),
  testPinnedSpacesStayOnTopAboveALine (menu and palette, the line only with both groups, Recent leaves pins),
  testDraggingASpaceAboveTheLinePinsIt (the first pin by drag, grabbed by its name, then unpinned by drag). The pin
  tests run in their own config folders.
- **Runs.** CI 42943686518 (11 chosen tests, before the flicker fix) and CI 42949477329 (10: the pin tests, the
  row and tab drags, Recent, Settings search, the palette, scroll into view, new window), green.
- **Review.** Three rounds: a strip that pushed every row 30 pt on any space drag (now an overlay), the line 4.5 pt
  off the gap's middle, pruning only in the visible sidebar (now every snapshot), palette places not pins first, a
  drag pin sent to herdr's end, a pin zone only a centre grab could reach, and the line drawn under the fade's mask;
  all fixed.


88. Onboarding v4 feedback (Track Y5; screenshot `.build/fb57/r7-ob-7.06.24.png`):
    "- for some reason app window colors are different from original like its bit more light, in the screnshot i have
    onboarding screen along with original app in the background, compare the background colors, tab color, sidebar
    colors etc and verify and understadn why recordings have different colors, is it because of any background it
    has? use plain dark background for dark theem and plain white background for light theme
    - in the first recording, in the right pane we show some node test thing, instead of that can we show like build
    is compiling, like may be like cargo compile, show line by line as they compile showing the progress
    - let's reduce gradient point to 50% from 55%, that onboarding agent knows about what i am talking about
    - in the second video, for the markdown content, remove extra empty lines between headers and checkboxes, and the
    space switching animation is bit slow and jagged in the sidebar, can we fix that? also stay in the switched space
    for sometime, it stays very brief and the video loops
    - too much movement in the third video, just show an agent whic has its response already, first in tui view and
    then switch to TUI view, also make sure thw window is active in the entire recording, i see in the beginning of
    video, the window is not active and it got active later, and the caht view flickers when switched, so make sure
    to open it before so when switching the flicker is not there
    - in everything you need section, the text is going two lines, let's rephrase it so it fits in one line like every
    other screen, also we should change the video recording, instead of showing like we are opening panes from cli, we
    can show more like claude code is opening these panes, show a claude code tui, where the agent has finished its
    work and opens git tree and the deployment plugin on the side similar to how its now, just not open the browser
    down, instead open the browser in a new tab. we don't need to switch to the browser pane, and in the text as well
    we should mention like either you open the pane or let agent opens panes etc, make sure to keep it one line
    - and in the final remote screen, we are just opening the menu, but that doesn't seem clear, we should show
    clicking on add machine and typing certain machine name in ssh and stop."
    Later, on the Everything you need clip: "in the recording i noticed, we are providing exact ovvi commands to claude
    code to open the panes, instead point the claude code to ovvi skill before itself and keep the session ready, and
    there shoulnd't be a rpopmt, instead it should look like claude is done with its work, and opening git, deploy panes
    and then browser pane for user review"; "in its recording i noticed claude code permission propmts were coming, it
    should probably run in yolo mode to avaoid those"; "its claude code opening deploy plugin beisde but opening working
    tree in another tab, we should also not have any tabs in that workspace, so we can clarly see the brwoser tab
    getting opened, and open git tree, not working tree".
    On the takes: "in the second clip, wait for sometime before opening pane, split pane, then after a sec open a tab,
    then wait for some time and then switch the space, and the space that is switched should be a new one which we
    didn't see in previous screen"; "in the third clip as we are just showing chat view and tui view and no other
    movements, let's just make it two images one in chat view and one in tui view and then we fade between those two
    images and loop"; "in the fourth clip, it is not very clear that agent is opening those panes, i think that text is
    bit hidden under our shadow and text, lets ask claude to show some text or something after so we can see clearly
    that claude opnede, make it subtle it shouldn't look like this is done for demo btw, also once all are opened and
    claude responded, wait for sometime before looping" ("make it 4s"); "in the last clip as well, wait for sometime
    after typing ssh name, like it loops too quickly, maintain slow pace overall, don't rush" ("typing should be fast
    for remote ssh one, keep it same"); "herdr logo don't change colors, just use official log and use some border or
    something around it, and once installed idk why we are showing our ovvi logo again? we should show green check
    mark instead"; "on the clip where agent opens panes, after they open the panes, let's fade and skip to show the
    full agent answer ... once full text is shown we wait for 4s and then loop".

89. Pinned spaces and sorting, second pass (Track B2):
    "- let's change the sorting to specific to session instead of window and all sessions follow the default ones, if
    their sortign is manually changed it should be remembered for those sessions
    - when sort mode is recent i know we disable drag and drop for workspaces, but drag and drop should work within
    pinned area if user wants to sort the pinned ones and also user should be able to drag and drop to a pinned region
    to pin the workspaces, only dragging and moving workspaces within non pinned region should be disabled when
    sorting mode is recent
    - drag and drop animatino when i leave the mouse, it snaps immediately like without animation, check tab pill
    animations, we should basically do something similar to to it just in vertical directions, like after leaving it
    should move and fade in/out instead of just snap immediately, idk if i am explaining correctly understand tab pill
    animations and do something similar and make sure not to overcomplicate the code and keep things simple please
    - its not very clear when i am dropping to pinned region, on first drop the line separatro shows in blue color,
    line seaprator shouold show blue even when i am dropping next one, so its evident that the dragged space is going
    to the pinned region
    - spaces sorting animations are inconsistent, like when the spaces are moved around we should always show
    animations, like for exmaple when i use right click and do move up or move down i don't see animation, and when i
    cahnge sorting before i used to see the spaces animate and change their positions, now i don't see that, make sure
    to show the spaces moving animation all the time
    - also for pinned region, whenever you drag, instead of just line, show like add to pinned or something,similar to
    how we show new workspace when i am dragging a tab onto the sidebar, like a rectangular region instead of one
    line, even if there are already pinned spaces, that region should be shown below the last pinned space"
    Added later: "also include one more feature called hide all except pinned (rephrase that better), basically i
    should be able to hide other workspaces except the pinned ones, should be available from cmd+k or right clicking
    on sidebar"
    Then: "not when right clicking on space, only on empty sidebar or at the top on the session header".
    Then: "hiding spaces should hide their notifications as well btw".

### Tart VM plugin, second pass (p57-tart-plugin-v2)

The user: "tart vm plugin shouldn't show that localhost urls … we just show the vm screen, show vm title and any
metadata info in the header … instead show a button which opens the vm in original tart vm app … our plugin should use
webkit directly instead of using browser plugin … if not we should provide that support".

- **Fix.** The plugin's own card draws the VM's screen (noVNC in its page): no Browser card, no address, no reload.
  Row 1 is "Tart VM ‹vm›" (the page's title), row 2 "Running · macOS 27.2 · 4 cores · 8 GB" and **Open in Tart**.
  The bridge only joins the card's WebSocket to the guest's VNC (Origin `ovvi-plugin://tart-vm`).
- **Ovvi's part.** A manifest field `connect` lists local `http`/`ws` origins (127.0.0.1 and a port: CSP takes no
  IPv6 host);
  they join the page's `connect-src`, and the confirmation names them. Spike: a custom-scheme page is a secure context
  (noVNC's Apple authentication needs WebCrypto), and its WebSocket's Origin is `ovvi-plugin://<id>`.
- **Decisions.** Only the process that runs a VM can draw it (a `VZVirtualMachineView` in `tart run`; Tart has no
  display API). So VMs start `--suspendable`, and **Open in Tart** runs `tart suspend` and then `tart run` with a
  window: the same VM, with its state, in Tart's window after about 8 s (spiked on a clone: a file in `/tmp` and a
  `--dir` share survived). Closing Tart's window suspends the VM; the card's Start and Connect, or the next
  `make vm-e2e`, resumes it headless. The button refuses while a test run holds the VM lock. A card loaded again
  shows its VM but never boots one by itself.
- **The user's rule (VM or CI).** "use tart vms only for ad hoc runs, and should fall back to github ci ad hoc runs if
  the vms are busy … if agents is testing already defined flow adn there is a test case already exists then running
  in github ci should be fine, but if exploring certain thing and want to take screenshots and review and improve
  then tart vms are good, again use the lock for tart vm". So `make vm-e2e` no longer queues: a busy VM stops it
  with "the VM is busy", and the agent uses CI. Full runs go to CI only (a full VM run was started and stopped).
- **Cause (a test runner killed in the VM).** The guest had about 4 GB free of the image's 50 GB, and macOS purged
  the runner. **Fix:** a 100 GB disk (56 GB free; sparse, 37 GB on the Mac), each run tidies its guest leftovers,
  also after a kill (a killed run had left its app, herdr servers and run folder), and a run stops under 8 GB free.
- **Runs.** `testAPluginPageReachesOnlyTheLocalOriginsItDeclares` and `testAPluginCardAsksAndItsPageSetsItsSettings`
  green in the VM.

### Tart VM plugin, third pass (p57-tart-plugin-v3, v4) and the plugin folders

The user: "when connecting there is some different colored box instead of pane color, when connecting just show text
and use pane background, don't add any solid color bacakground"; "can we add rounded borders to the screen sharing
content? … similar to the pane border radius"; "mouse cursor doesn't work inside the vm area, i see mouse cursor
disappears, and secondly does clicking on open in tart doesn't end the vm and restarts it right? … once i open the
plugin, list all vms, and have option to stop them or open them and create a new one … closing plugin shouldn't stop
the vm btw. it just disables that screen sharing thing"; "for tart plugins, can we keep it our repo only? … no top
level folder, let's have plugins/ folder and within that may be two sub folders on for builtin and for these other
ones".

- **Fix (plugin 0.3, 0.4).** Status pages are text on the card's fill (no panel color). The screen's canvas has the
  card's 10 pt corners (CardSurface.radius). The card's home is the VM list, every time it opens: Open (starts a VM
  that is off, with no window), Stop (asks; `ovvi-tart stop`), New VM… (a name, the cost, a question with a VM
  running); ‹ All VMs in the header. golden-gate is never started, stopped or deleted.
- **Cause (the pointer vanished).** macOS Screen Sharing sends no cursor shape (no Cursor or VMware cursor rects, an
  RFB probe under the VM lock) and draws no pointer into a VM's screen, so noVNC keeps the canvas at `cursor: none`.
  **Fix:** the system arrow while noVNC has no shape.
- **In use (generic).** The user: "we want the plugin to be generic not specific to any ovvi tests". The plugin
  defines one convention: a tool holds `~/.config/ovvi-tart/locks/<vm>.lock` (lockf/flock), optionally naming
  itself in `<vm>.owner`; while it is held the card sends no pointer or key (noVNC `viewOnly`, also until the bridge
  first answers), shows "In use · ‹owner›", and Stop and Open in Tart refuse. `ovvi-tart in-use` reads the lock with
  `F_GETLK`, never taking it (a probe would fail a holder's `lockf -t 0`). Ovvi's VM lock is now that lock for
  `ovvi-test` (`/tmp/ovvi-vm.lock` is gone; one lock).
- **Open in Tart** is a suspend and a resume (about 8 s): apps, files and processes survive; connections into the
  guest (VNC, ssh, `tart exec`) drop. Closing the card ends only its VNC connection (checked: the bridge's connection
  to `:5900` closed, the VM ran on).
- **Folders.** `plugins/builtin/` (explorer, git, template: built and carried by `make web`) and `plugins/extra/`
  (tart-vm: checked by `make lint`, installed from its folder, not carried). The plugin moved from its own repo
  (`~/code/ovvi-tart-plugin` at 5051b1a) as a copy, then 0.5 (the in-use lock). `scripts/vm-test.sh` runs
  `ovvi-tart` from the tree. A card's next screen replaces a bridge LaunchAgent made from another folder.
- **0.6, Delete.** User: "for tart vm, let's have option for delete vm as well, and when stopping vm the toast should
  show red button, also for stop and delete, delete should be shown only for stopped vms". Delete shows on a
  stopped VM only (a suspended one keeps its state: no Delete), never on golden-gate; it asks with the VM's size and
  a red button, as Stop now does (`destructive`). `ovvi-tart delete` refuses while the lock is held or the VM is not
  stopped, and drops the VM's kept args, macOS and log. No pictures: a dev build with the card needs the Mac's
  screen for longer than one short hold.
- **0.6.1, button gaps.** User: "the stop and open button in the plugin has very less space between, while in the
  toast stop button and cancel has too much space, keep the spaces consistent please". **Cause:** the row's buttons
  sat in a `div` no flex rule matched (0 px apart); the toast's HStack used 10 pt. **Fix:** both use the app's 8 (its
  other button pairs and NoticeCapsule); the plugin API has no spacing variable, so the CSS says 8px. Every toast's
  text and buttons are 8 pt apart now. Measures: ~/Downloads/ovvi-research/tart-vm/v7/measures.md.

### Track B2 (item 89)

- **What happened, item by item.** (1) The sort was the window's scene storage. (2) Recent worked on the old code (a
  probe dragged within the pinned ones, pinned and unpinned by drag), but with nothing pinned a drop pinned only within
  8 pt of the list's top, and with pins nothing showed where a pin would land. (3) Space rows had no landing at all
  (Track B removed it). (5) Move Up and Move Down never had a motion; the sort jumped since its `.animation(motion)` moved
  onto a custom binding that wrote the window's environment binding (it animated through `@AppStorage`'s binding
  before, through the same menu).
- **Fix.** Sort Spaces and Show Only Pinned Spaces are the session's, lines beside the pins in the sidebar's defaults
  ("‹machine› ‹session› sorted recent", "… only pinned"), all three observable on `HostStore`. The sidebar is one
  `ForEach` of rows and one place under the pinned ones (`Item.pins`): the line, or while a space is dragged the
  "Pin Space" region (`DropRow`, shared with New Space), so the slot math is "place after the drop less place now" over
  one list, with no line-gap terms. One `.animation(0.2 s ease-out, value:)` keyed on the shown order (with the line's
  place and the drag) moves every reorder; menu actions run once the menu has closed (`afterMenu`). At the drop the row
  shows at the drag image (an offset set outside the motion), then that offset and its gap go to 0 in the rows' motion,
  so it moves from the image to its place while fading from 0.4. The tab capsules' keyframe landing (`Lands`) did not
  show on space rows (the frames showed the row leaving its gap), so rows use the plain offset. Also: under load
  DragGesture's first change came once the pointer was over another row, and the drag image showed that row; it shows
  the grabbed place now.
- **Show Only Pinned Spaces.** Hides unpinned spaces but any a window shows; a hidden space's panes get no state (one
  place, `showStates`), so the Dock badge, the Dock menu, the row and tab icons and notifications (herdr's and
  `ovvi notify`) leave them out; turning it off shows their states with no burst (notifications come only from
  `Seen` changes). Off when the last pin goes.
- **Decisions.** The region lights by the pointer; slots go by the drag image's middle (the header, not the agents).
  The region pushes the rows below it down by 40 pt while a space is dragged, in the motion. A typed filter shows rows
  at once (not in the motion's key). The ⌃⌘ keys, the overview and the palette's places skip hidden spaces.
- **Measured** (VM recording, frames on change up to 60 fps, row tops by template match, 2x px). Manual drop: the
  image's top 353 in the last frame before the drop; the dropped row 352 → 322 → 309 → 307 → 308 → 312 (its reset starts
  a turn after the rows' move: a 2.5 pt dip), the rows around it 311 → 287 → 266 → 253 → 241 → 232;
  Move Up, the sort and Show Only Pinned Spaces move in 4–6 frames after the menu's fade. The old code: the sort and
  Move Up jump in one frame, the drop shows the row at its slot at once. AppKit draws frames right after the drop here:
  B's "no frame for 0.3–0.5 s" did not reproduce, and the tab capsule's landing takes the same path. Sheets (dark,
  light, before, after): `~/Downloads/ovvi-research/p57b2/`.
- **Known.** With nothing pinned every space drag pushes the whole list down 40 pt (the region on top), so a drop aimed
  before the drag lands a row short; the row-drag tests aim past it. A drag that starts late with the pointer already
  where the region appears, and then holds still, gets no update once the region is laid out (it decides on the row
  under it); a moving pointer lights it. A window's selection reaches `hidden` on its next selection or snapshot.
- **Tests.** PinTests: each session's order (two windows follow one session, another session takes Settings'), the pin
  region lit on the first and the next drag (a row with an agent held by its name), placing among the pinned ones and
  unpinning, Recent (pin onto the region, reorder pinned, refuse unpinned), Show Only Pinned Spaces (in view stays,
  badge, `ovvi notify`, Show All, last unpin), and every reorder's motion (`sidebar.moves`: a wiring check that each
  order change carries the motion; the frames are the strips). XCUITest reads frames after the app idles, so a test
  cannot see the motion's frames.
- **Runs.** The new tests on the old code: CI 42969024976, all five red (no lit region, the other window kept its own
  order, no `sidebar.moves`, no Show Only Pinned Spaces). VM: the six PinTests, the row and tab drags, Recent, the row
  menu, green. CI 42974865786 on the head (17 chosen tests: these, the row and tab drags, Recent, the row menu, notify, Settings search, the palette, the Dock badge), green. Review, two rounds: the region lit by the whole row's middle (not the pointer), a landing not shown frame by
  frame, a refused gap with Show Only Pinned in Recent, worktrees outside the motion's key, states stale after a window
  closed, a session test that passed with Settings ignored; all fixed.
- **For the user.** Drag a space with nothing pinned and with pins, dark and light: the region "Pin Space" shows under
  the pinned ones (on top with none) and lights blue under the pointer on every drag; drop on it, among the pinned rows,
  and under it. The dropped row moves from where you let go into place and fades in; Move Up/Down, Sort Spaces, pin and
  unpin, and Show Only Pinned Spaces all slide. Sort Spaces in one session, then another session: the other follows
  Settings ▸ Agents ▸ Sort spaces; a relaunch keeps each. With Show Only Pinned Spaces on, a hidden space's agent sends
  no banner and leaves the Dock badge.

90. Sidebar hover on the wrong row (Track B3; video `.build/fb57/r7-hover-11.16.11.mov`): "i tested the new sidebar
    changes, everything is good, one weird issue is when i hover mouse on certain worksapces sometimes it focuses on
    something else, it happens when i pin things, its not consistent, it happens randomly"

### Track B3 (item 90)

- **Cause.** Track U's one pointer tracker found the hovered row by frames each header and agent line took in the
  list's space, from inside the row's `.offset`: the drop's landing and the drag's slide (the pin region's 40 pt and its
  gap). SwiftUI did not always report the offset's end: in the VM, after a pin by drag the dropped row's targets stayed
  at its landing offset (240 pt up), so nothing lit over it; in the user's video the pinned rows kept the slide's 50 pt,
  so the pointer lit the row 50 pt under it (one or two rows off), and rows under the line were right.
- **Fix.** Each target takes its frame in its own row (`WorkspaceRow.space`), placed by the row's frame, which is
  taken outside the offsets; a row that moves aims again.
- **Test.** `testThePointerLightsTheRowUnderItAfterPins`: three spaces with two agent lines each; after a drop on the
  pin region, a menu pin, a drag among the pinned ones, Move Up and an unpin, the pointer over each row lights that row
  (`sidebar.lit`, shown with `-recordMotion`).
- **Runs.** VM, the old code: red after the drop on the pin region (over the dropped row, nothing lit). CI 42983421875
  on the review's head: 10 of 11 green (the pin tests, the row drags, hover cards, the stress test); the new test's drag
  among the pinned ones aimed at a header, not past the block's middle (fixed, green in the VM). CI 42985378561 on the
  final head: the new test and the agent row's hover card, green.
- **For the user.** Pin a space by dragging it onto Pin Space and from its menu, reorder the pinned ones, then move the
  pointer slowly over every header and agent line: the lit row is the one under the pointer.

91. Faster UI tests (Track CI2; report `~/Downloads/ovvi-research/ci-speed/report.html`): the user approved the
    coverage-neutral cuts, the 4 drops, 31 merges and 5 slims, and clearing the VM's notification dialog: "yep go with
    1,2 and 4, no paid ones".

### Track Y5 (item 88)

- **Cause, colors.** Two causes, both measured in sRGB. (1) The recorder filmed with a ScreenCaptureKit filter that
  names the windows it takes. Such a capture draws the window's behind-window glass over nothing: dark 33 and light
  241, whatever is under the window. The same window on screen shows 26 over black and 249 over white (the user's
  screenshot: 27). Only a filter that leaves the other windows out draws the glass from what is really under it. Even
  then, leaving out the desktop's own windows brings the 33 back. (2) The clips were tagged bt709, and AVFoundation
  plays sRGB pixels with that tag lighter (33 as 36, 43 as 49, as in the screenshot). They are now tagged sRGB, and
  they play as encoded.
- **Fix, colors.** Each film keeps only the window's rect. Its filter leaves out every other app's window, those off
  screen too, but not the desktop's, which lie under the backdrop. The filter is rebuilt every 0.25 s for new windows.
  A new window over the rect marks the take, and the script deletes the film and fails the take. The backdrop (black
  or white) covers only the window plus 80 pt. It sits right under the window and lives only while a film runs (it
  ends by itself at 170 s, the film at 150 s). Measured, the new clips' top bar and sidebar: dark 26, light 249, the
  same as the real window on screen over the backdrop.
- **Decisions.** The orchestrator chose the leave-others-out filter with the intrusion rule over a take-only filter
  (safe by construction, but 7–8 levels off) and over recording-only app code. The build in clip 1 replays a real
  cargo build's lines (no Rust crates offline), with cargo's pre-1.77 Finished line, which fits the pane. The scene's
  Claude Code approves every tool through a PreToolUse hook in its own settings: `--dangerously-skip-permissions`
  shows "bypass permissions on" under the prompt. It runs Opus 4.5, as the scene's stand-ins show it.
- **Cause, the jagged space switch.** The recording, not the app. The old take clicked the space twice and walked the
  window's accessibility tree between the clicks, and each walk holds the app's main thread. So the highlight came in
  three steps over 0.35 s, 1.1 s after the click. Clicks on camera now go to spots found before the film starts:
  hover, press, then the selection about 0.14 s after the mouse-up, each in one frame with no fade (60 fps track: 20,
  26, 45). The switched space holds 4 s.
- **Found on the way.** SCRecordingOutput's finish callback often never comes: the film waited on it forever and kept
  its backdrop up over the user's screen. It now waits 3 s at most, and a stdin read ends it. A `withTaskGroup` waits
  for all its children, so a timeout child kept the film running until the timeout. A menu item's title with a space
  shifted the fields of `ax find`. A full-screen backdrop and a hung film locked the user out twice: the backdrop is now
  window-sized and short-lived (lessons.md).
- **The second pass.** Clip 2 splits at 1.5 s, adds a tab, then switches to docs, which no other clip shows (opened
  once off camera, so its cards are drawn). Clip 3 is two frames of its film, TUI and Chat, faded into each other.
  Clip 4: Claude Code's memory asks for a short "Open for review / What changed" reply, which sits above the shade;
  the clip keeps the cards opening (cut where the Git card's page is still blank), then fades to the whole reply and
  holds it 4 s. Clip 5 is slower, its target still typed fast. The herdr step shows herdr's own logo.png on a bordered
  tile, and a green check on the same tile once herdr is installed.
- **Review.** A window of another app could sit between the backdrop and the window, and the glass would blur it:
  the recorder now raises the window before the backdrop, and the film marks any other app's window over the rect or
  under it above the backdrop, whatever its alpha. A failed take deletes its film; the backdrop ends with its parent;
  "recording" comes with the first frame, so the steps' times are the clip's; the plugins take checks the cards'
  places.
- **For the user.** Watch the five clips in both looks in the report. Claude Code's footer reads "manual mode on": the
  hook approves every tool, and the mode label stays.

92. A local page in a browser card can't load files from other folders (Track W2): the landing page's clips in a
    sibling folder were blocked, because the card grants read access only to the opened file's folder. The user: "yeah
    let's fix that in ovvi browser card".

### Track CI2 (item 91)

- **Cause, the quit between tests.** Not the app: XCUITest ends the app with a kill (gone in 0.2 s) and then checks
  for its exit once a second, so each relaunch waits about 1 s more. A kill by the e2e helper left XCUITest's state
  "running" for 5 s and more, so the next launch waited longer: dropped. The app's own quit (⌘Q) was slow, though: its
  marks went one herdr run at a time (9 runs: 0.85 s on a busy Mac, 0.16 s at once), and the 1 s wait cut the rest. The
  quit's marks now go at once, and an earlier batch sends only its unmarks once the quit starts.
- **Fix, launches.** setUp skips its launch for the 60 tests that launch before they use the app
  (`OvviUITests/OwnLaunch.swift`; `scripts/check-launches.py` in `make test` keeps the list exact) and ends the earlier
  test's app instead, so nothing sees what such a test sets up.
- **Fix, the cuts.** The report's 4 drops, 30 merges and 5 slims, each merged test one flow whose parts start with
  `step()`: an activity in the result, and the part's name before each failure's message. The longest merged tests
  take 45–63 s (the remote chat test runs three agents).
- **Decisions.** testALaunchWithNothingToRestoreConnectsToNothing stays a test of its own (the first-launch path).
  Not done from Appendix C, as not honest: DragTests' notice waits (the next write clears an error notice, so a later
  check passes even when the drop failed), FilesTests' Forward waits (a wrong Back comes through WebKit with no bound),
  PinTests' 2 s (the app's Recent order holds 1 s after the pointer leaves), LatencyTests' key() sleeps (one run
  cannot prove the turn counts), LongChat's sign (CI's is tried first already).
- **Cause, the VM's dialog.** `screencapture` through `tart exec` or ssh (agents' screenshots of the guest): macOS asks
  whether that program may go on capturing the screen, a UserNotificationCenter alert, again after a month. Two more
  asks would take the tests' clicks: whether the tests' app may send notifications (a banner over the window's top
  right) and "App Running in Background". `scripts/vm-alerts.py` answers all three before each VM run, and the script
  closes an alert still open. Also found: in the VM the tests' fixtures were missing at the checkout's path, so every
  fixture test failed there (the welcome's herdr install); the path now links to the run's copies.
- **Runs.** Chosen-tests runs 42986570225 (the launches, the quit's marks: 11 green) and 42991076749 (the review's
  fixes: 12 green); the helpers' 42983298014, 42984043803 and 42984177251 (every merged test green). Full run
  42988751759 of the merged suite: green, 271 tests, 4729 s of tests (5051 s for 289 before), 25.5 min and 94
  runner-minutes (before: 22.5–23.4 min, 92–93), with one shard on old times 5 min over the rest; the times are now
  refreshed from it (the plan: 946 s a shard). One VM run of the welcome tests: green, no alert. The user's call:
  the proof pair 42993147651 and 42993159009 runs after the push, unread.
- **For the user.** In the VM, the welcome opened a second time from Settings showed a spinning cursor for about 5 s
  before it drew (CI: under 5 s). It may be worth a look on a slow Mac.

### Track W2

- **Cause.** The browser card loaded a `file://` page with read access to its own folder only, so media in a sibling
  folder under the home folder failed (WebKit's page process reads `/private/tmp` anyway, so a test there passes on
  the old code).
- **Fix.** Read access to `/`, as WebKit already gives a file page opened from a link or the history. WebKit's file
  origin rules stay: scripts still cannot fetch other files. Plugin pages (`ovvi-plugin:`) have no file access path.
- **Runs.** None: the new test (`testALocalPageReadsAndOpensOtherFolders`, in the home folder) waits for the final CI
  round. The reviewer's headless WKWebView probe showed a sibling image and an mp4 under `~` blocked on the old access
  and loaded on the new.

93. Terminal links (Track L): "yeah go to directory opens up file picker, let's disable go to directory in remote
    machines for now" · "ctrl doesn't show underlines" · "for the cmd+click and option+click we still don't show
    error toast when file not found or path not found, its just silent when i cmd click invalid path" · "we need better
    parsing for the urls in terms of file paths, urls etc, there are many edge cases where wrong urls are picked,
    especially in terminal when some /commands are mentioned, and also sometimes the next sentence in url is captured as
    well, figure out all edge cases and fix the parsing well" · "and when you do cmd+click or option+click in a floating
    pane, we should show open that link in another floating window irrespective of the cmd+click or option+click"
94. New tab placement and open toasts (Track N2): "we have move pane to tab and choose new tab option on right clicking
    a pane, we should put that tab just beside the current tab, similar to how we handle cmd+click, instead of keeping
    it at the end of current list of tabs" · "and when some process or agents open certain pane or tab, we show a toast
    saying x opened y, but that toast doesn't stay for long, it goes away quite quickly before i can click on the
    toast, let's keep them for few seconds"
95. Compat leftovers and licence (Track C2): "what is the license issue? what should we change?" · "what are the name
    changes in settings? its okay if we lose any settings for now, that's okay, we can also reset all app data
    locally, so i can start fresh and see how it looks as well" · "any cleanups are skipped coz of backward compat, its
    okay do them if needed"
96. Then "do one last ci run, and make sure everything is green, don't let individual agents wait on ci".
97. Reconnecting look (Track F2): "when reconnecting to remote machine, we now show a big grey rectangle saying
    reconnecting, i think we did that coz, earlier there was some text overlap, but that grey rectngel looks ugly, can
    we improve that and make it fit to our ui better?"

### Track N2 (item 94)

- **Cause.** Move Pane to Tab ▸ New Tab sent only `pane.move` to a new tab, which herdr adds last; the agent's
  notice with **Show** went after 4 s like any notice, Retry's after 10 s.
- **Fix.** New Tab places the tab as the opens from a card do: right after the pane's tab, shown there from its first
  frame (`placeBeside`, then `tab.move`). The card's menu, View ▸ Pane and the palette share the one command. A notice
  with an action (Show, Retry) stays 6 s, and stays while the pointer is over it; it goes when the pointer leaves if
  its time is up.
- **Decisions.** ⌘T, `+` and a drop on `+` or the bar's end stay last, as in Safari (the design). New Tab is disabled
  for a pane alone in its tab: herdr would close the tab and make it again in the same place. Retry's notice went
  from 10 s to the same 6 s: one value for notices with an action, and the pointer holds any of them.
- **Runs.** None: the new checks (in `testContextMenuSplitsLeftRenamesAndMovesToNewTab`, and
  `testAnAgentsNoticeStaysUnderThePointer`) wait for the final CI round.
- **For the user.** Right-click a pane in a split ▸ Move Pane to Tab ▸ New Tab: the tab lands right after its tab.
  Hover an "‹agent› opened …" notice: it stays until the pointer leaves.
98. The first browser card after an install hangs (Track W3): "whenever app is reinstalled and on first open on browser
    plugin it hangs a bit and then after few seconds it recovers, idk why this always happens, subsequent browser plugin
    loads are generally fine, so when the system was at load, i reinstalled ovvi and opened the fresh .app and opened
    browser, it hanged for some time and then system crashed, investigate if there's something we should take care
    here, and fix accoridngly"
99. Sessions after a restart (Track A2): "after restart, when i opened ovvi, it says default is not running, and start
    default, whenever we restart and ovvi is opened, we should restore and start those sessions automatically, don't
    ask whether to start session or not"

### Track C2 (item 95)

- **License.** No GNU libintl is linked. libghostty-spm (pin `1d84cf66`, 2.2.2026110702) builds Ghostty with
  `-Di18n=false`, its patch `0021-no-libintl.sh` links libintl only with i18n on, and its verify script refuses an
  archive with a `libintl_` symbol. The app's code (`Ovvi.debug.dylib`, libghostty linked in: `ghostty_surface_new`
  defined) has no `gettext`, `textdomain` or `libintl` symbol and no dynamic libintl. The repo had no license: it is now
  AGPL-3.0-only (`LICENSE`, gnu.org's text); the plugin API's types and the template are MIT. Every bundled piece goes
  with AGPLv3: MIT, BSD, ISC, Apache-2.0, MPL-2.0 (z2d; noVNC in the separately installed Tart VM plugin), OFL and
  GPL-2.0-with-font-exception fonts (data, not linked), CC0 icons, and in Shiki's bundled grammars and themes GPL-3.0
  (ada, gnuplot, nginx, org, racket, aurora-x, compatible) and 33 grammars with no declared license (tm-grammars'
  NOTICE). Acknowledgements lacked the default plugins' web libraries other than CodeMirror and pdf.js: added.
- **Names.** The sidebar's suite `dev.ovvi.app.agents.‹config›` → `‹bundle id›.sidebar.‹config›`, `agentsOpen` →
  `foldsAndShelves`, `pinnedSpaces` → `spaceChoices`. The other keys, files and scene ids already say what they hold.
- **Compat leftovers.** OpenCode's first `getConfig` path (`_client`) never matched a TUI plugin: TUI plugins exist
  from OpenCode 1.4.0, get the SDK's v2 client, and its field was `client` from 1.2.0 on (checked in the npm packages).
  The browser's `Version/18.0` was stale (Safari is 27.2 here): it now follows the macOS version, as Safari has since 26.
- **Reset.** `scripts/reset-app-data.sh`. The old suites (`dev.ovvi.app.agents.*`) are left to a one-off command.
- **Runs.** None: `testABrowserSaysItIsThisSystemsSafari` waits for the final CI round.

### Track A2 (item 99)

- **Cause.** A restored window read the machine's session list and skipped every page whose session was not running.
  After a restart of the Mac every session is stopped, so the user had to pick and start each one by hand.
- **Fix.** A restored window opens every saved page that the machine still lists, and a page found stopped starts as
  its Start button does ("Starting ‹session›…", then the page; a failed start shows "not running" with why and Start).
  The decision is made once, on the page's first read with a session list, in the same turn as the failed read, so
  Start never draws first and a later Stop is never undone. A restored remote window connects as a machine window
  does (it asks what ssh asks), then starts its stopped pages. ⌘N's view and Open Session stay manual.
- **Decisions.** The start-on-open flag (`-session`, the new-window pick) now starts after the first failed read
  instead of before the first read: one path, the Start button's, for every automatic start. A session deleted since
  stays skipped; on a remote machine that does not answer at launch it cannot be told apart, so its page opens and
  its start makes a new session of that name.
- **Runs.** On this Mac under the GUI lock (no VM): 6 of 8 green (the start, stop and restore tests of FailureTests
  and WindowTests). `testRelaunchRestoresEveryPageAndStartsTheStoppedOnes` and the floating-window relaunch test failed
  at their first, saving launch, before any restore: it came up with three windows of `one` right after
  `forget-windows`, in steps this change does not touch. They wait for the final CI
  round.
- **For the user.** Restart the Mac (or `herdr --session default session stop default` with Ovvi quit), then open
  Ovvi: the window comes back and its sessions start with no click.

### Track F2 (item 97)

- **Cause.** Item 83 put Reconnecting on a large glass panel in the middle of the dimmed cards, so its words never ran
  through a card's text. The panel was the only state drawn that way.
- **Fix.** Over cards, Reconnecting is now a notice: a capsule at the page's bottom with a spinner, "Reconnecting to
  ‹machine›…" and the reason as a smaller second line, under any notice and over the control capsule. A page with no
  cards (a first connect that failed, a space with no tabs) shows the plain loader, as Connecting does. The page still
  owns the state: cards show none of their own.
- **Decisions.** Three options as pictures, dark and light (`~/Downloads/ovvi-research/p57f2/options/`): A, the bottom
  capsule (chosen: the same look as the notices and "Controlled in another window", which also dims the cards); B,
  the plain loader over cards faded to 0.12 (faint terminal text still ran under its words); C, a capsule in the
  middle (it still sat on the cards' text).
- **Runs.** On the host under the GUI lock (the VM was off limits by then): a throwaway picture test, green, dark and
  light, over cards and with none. `testAReconnectingPageShowsItsStateOnce` needs CI's sshd; it now also fails if
  the centered loader comes back over cards.
- **For the user.** Drop a remote machine's link with cards open: a small capsule at the bottom says Reconnecting, and
  the dimmed cards stay readable.


### Track L, item 93

- **Cause.** libghostty found the terminal's links with its own fixed pattern (`link-url`; libghostty cannot take
  another): its path branch takes any `/word` (`/compact`) and the words after a path up to one that ends in `.` or `/`
  (`/tmp/a.txt then more.`). A path that matched nothing on This Mac fell through silently, and Go to Directory on a
  remote card showed This Mac's folder panel.
- **Fix.** `link-url = false`; the app reads libghostty's cells and finds links itself (`TerminalLink` in HerdrKit,
  106 table cases), draws its own underline under ⌘ or ⌥ alone, and shows "File not found: ‹path›" (checked on the
  card's machine) or "Ovvi can't open ‹address›" instead of silence. OSC 8 links stay libghostty's. From a floating
  card any open that would go to a new tab or the side floats in a window of its own (browser cards too). Go to
  Directory is off on remote machines.
- **Decisions.** No bare domains (`example.com` reads as a file name too). An absolute path needs two names, an
  extension or a closing `/`, so `/tmp` alone is no link either. Rows join when the row above fills its width: herdr's
  frames carry no soft-wrap flag. libghostty-spm keeps its surface handle internal: a `Mirror` reads it (ponytail).
- **Runs.** On this Mac under the GUI lock: `testCommandClickOnALinkOpensIt` (now also `/compact`, the words after a
  path, the ftp and not-found notices) and `testALinkInAFloatingCardOpensInAFloatingWindow` green. The remote Go to
  Directory check (`testAFileDroppedOnARemoteCardPastesItsCopysPath`) needs CI's sshd: final CI round.
- **For the user.** ⌘ and ⌥ over a long URL that wraps; `/compact` and dates show no underline; ⌘-click a missing path
  on a remote machine; ⌘- and ⌥-click in a floating terminal.

### Track W3 (item 98)

- **Cause, measured.** The first web card makes WebKit start three helper processes: a GPU and a network process, which
  all cards share, and the card's page process. WebKit starts the network process only once the page process runs. The
  user's log of the launch after the install (03:09, right after a restart, a busy Mac): GPU 12.6 s and page 12.5 s,
  then network 13.3 s more, so the page could load only 26 s after the card was made, and WebKit called it
  unresponsive until 03:10:00. Its next nine cards started only a page process, in 33–73 ms each. While the network
  process started, the whole Mac stalled: the system log fell from about 2,500 lines a second to 330–830, and the
  security agents (Defender, Santa, EndpointSecurity) checked each new WebKit process and its sandbox cache.
- **Not the cause, measured.** Ovvi's main thread: in `sample` runs on this Mac (load 70–85) a first card cost it about
  50 ms (`WKWebView` init), and it stayed 97 % idle also with the network process held stopped 10 s and an
  accessibility client walking the app's tree. A new code signature alone (the same app re-signed, its data kept)
  started the three in 0.1–0.3 s. The GPU watchdog acts only when WebKit has dropped a GPU process that still runs:
  the user's logs show one end in 8 hours (00:55, after WebKit gave up on it), none at a first start.
- **Fix.** 3 s after launch, when no web card shows yet, the app opens one hidden empty page in This Mac's browser
  store and lets it go once its page process answers. WebKit starts its processes then, one set as for one card; the
  GPU (4.2 MB) and network (5.3 MB) processes stay for the cards, and the page process ends. The first card then starts
  only its page process (103 ms here).
- **Decisions.** No prewarm of page processes for cards (WebKit makes one per card; many at once is what spikes a busy
  Mac). No load check before the prewarm: it is the same work the first card would do, only earlier.
- **Runs.** `testWebKitStartsAheadOfTheFirstWebCard`, on this Mac under the GUI lock: red on the old code (no network
  process of the app without a card, 105 s), green with the fix (6 s).
- **Found on the way.** herdr sends no event for `pane.rename`: a label written by a process shows in the app only at
  its next read (another event, or the 30 s check), 4–10 s in these runs.
- **For the user.** Reinstall, open the app, wait 3 s, open a browser card: it draws as fast as later ones.

### Final CI: Markdown mode after a link

- **Cause.** The app took a page's calls out of order. Its WebKit message handler was Swift's `async` form, which
  WebKit starts as one task per call off the main actor; the tasks reached the main actor reordered (21–33 of 3000 in a
  probe on an idle Mac). A link to a kept Markdown page sends that page's stored mode (Rich Text, from its last visit),
  then the card's mode (Source); swapped, Rich Text won (run 43050240152).
- **Fix.** The handler's `replyHandler` form, with its task made on the main actor: 0 of 3000 reordered. The Markdown
  pages read the card's look from its state and the settings, not from a variable all pages wrote (a hidden page wrote
  its own stale look there on a settings change).
- **Found on the way.** An error thrown in a page's handler of an app event reached no log (the app calls the page with
  no answer); the runtime now logs it. A failed UI test keeps the plugin pages' console as an attachment.
- **The title row** saying notes.md while the page showed other.md was herdr's rename arriving 0.5 s later, not a bug.

## Round 8 (items 100–108)

100. "we have cmd+click and option+click, can we also have cmd+option+click to open the link in default external app
     on their device" (Track L2).
101. "so after the update to links you did recently, when i select text on terminal, the colors are bit weird, make
     sure we have good highlight colors on both dark and light mode, also the underline right now is very bright and
     kinda very close to the text of the underline, idk its slightly different before ig, improve the underline so it
     looks good, and you also mentioned before when we did some ghostty changes, that the text is less bold overall, i
     am okay with it, but is it the default, coz in ghossty app i see text is bit more bold than what i see here"
     (Track L2).
102. "can we reduce number of commits loaded in git plugin by default to 100" (Track E2).
103. "and one more improvement to file explorer plugin, right now when we open a file we have one button to go to file
     tree, instead that button should open the file tree in sidebar beside the editor, not a separate pane, within the
     same pane like a file tree sidebar in regular text editor apps, and double clicking on any file from the tree
     should update the file same like before, and you should be able to navigate up the tree like in regular file
     explorer tree, basically think of it like this, when file explorer is opened, we have only tree, and one the file
     is opened it will show only file, now we can have a config option to show only file or open file and show file
     tree along the sidebar, and everything else in terms of navigation and everything stay same, whatever shown in
     file editor is updated only on double clicking and user can navigate the tree from the sidebar, they should be
     able to collapse that sidebar, and also close the file editor or markdown editor or image or video one that is
     currently being shown, hope that makes sense" (Track E2).
104. "so the reset script you gave has some issues, i ran the reset, most of the settings were gone, but when i open
     the app with fresh install, it still opened two windows with one window automatically connecting to default
     session, are these re missed by any chance? also i remember when i ran the script for the last one it showed
     operation not permitted, i tried rerunning with sudo but that didn't do anything, it just exited immediately.
     figure out if this is reset script issue or something else and make sure when we do reset, it should show only
     onboarding pane and once onboarding flow done then open the windows" (Track R2).
105. "and one more thing i noticed when i click add machine form cmd+n window that opened settings and i updated, then
     after that it opened another new window where it started connecting, why not the same new window that is already
     open?" (Track R2).
106. "let's improve agent chat ui empty placeholder, right now we just show the logo, instead can we improve it such
     that we show logo to the side or something and say what's on your mind? or some other phrases like that, where
     one will be chosen randomly, and the input will be shown in the center, basically center input and center header
     text and logo, as soon as user types a propmt and press enter, that input moved down and user submitted message
     goes up with animation and show our regular chat view, basically improve the empty chat view better and make it
     look more modern and beautfiul" (Track C3).
107. "in the markdown plugin, we currenly show pencil icon right can we update that to show read edit toggle buttons
     with text read and edit, that pencil doesn't look good" (Track E2).
108. "one more weird thing i am noticing mostly in remote machines, when i leave the tab for a while or i reconnected or
     something, and i select some tab or workspace, that pane very briefly shows terminal stopped with retry button,
     and then shows the terminal content, i am guessing here the content is not yet loaded instead of starting from
     blank and fading in, that error message is coming up, investigate the root cause, and fix it, so it doens't show
     unnecessarily" (Track S2).
     Item 101's screenshot: "i forgot to provide screenshots for selected text, see its bit weird color, pass on to the
     agent" (`.build/fb57/r8-6.07.11.png`). Then: "for the terminal url underlines and stuff, i noticed now, if the tui
     renders a link already with underline, now another underline gets shown when holding cmd or option, figure out
     better way to show these links overall for cmd and option clicks, it doesn't need to be just underline, just make
     sure our underline or whatever the way we do it, its ux is good and doesn't interfere with existing formatting of
     the text".
109. "one more thing when i am in chat view of an agent session i don't see its status in it pane title, like in tui i
     see working text with its icon, but as soon as i switch to chat, that status goes away, let's keep them
     consistent" (Track C3). Then: "okay i noticed this specifically when pi agent is waiting on agents or background
     job, like you are right now, so now when i switch to caht view i don't see status, but if there is active work
     going on this main session without just waiting on agents or stuff, that time it shows the status fine, weird
     stuff".
110. "yo one more thing, just realised in chat view currently no links support exist, can we use same url parsing in
     the chat view as well, and include supprot for cmd+click, option+click and cmd+option+click from chat view as
     well? also in chat view can we slightly increase line height, i feel the text is too congested, in chat view we
     should show underline by default not just on hover for links, and on hover some color or some changes, basically
     how any link would look in browser or any other app yk" (Track C4).

### Track S2 (item 108)

- **Cause.** `PaneTerminal.show()` took a failed stream for the pane's own as soon as it ran with the page live
  (`own = true`), and kept `.failed` while it opened the stream again, so "The terminal stopped" and Retry showed for
  the whole reattach: one round trip, long on a remote machine. A dropped connection ends every stream, and two ways
  hit it. A tab kept out of view (`PaneViewRegistry.recent`) keeps its stream, but the registry calls `show()` only for
  the cards in view, so the old `lost` flag (set by a `show()` while the page did not answer) never got set; selected
  once the page was back, the card judged the old failure by the page's state now. And a card in view whose page
  reconnected at once (no Reconnecting: a new ssh master came up) said "stopped" through its reattach too.
- **Fix.** A failure is the connection's until a try made while the page answers fails too. `show()` turns an
  unconfirmed failure into a load (`.idle`: the last picture, a spinner after 0.5 s) and opens the stream again; only
  that try's failure, followed by a snapshot, sets `own`. Leaving view or a pause forgets `own`, so a kept card judges
  again when it comes back. A confirmed failure's own retries go from failed to failed (`closed`), so the panel no
  longer blinks off for a refresh at each 5 s retry. `lost` is gone.
- **Decisions.** A truly stopped pane says so about two round trips later than before (one silent try first).
- **Runs.** The new test drops Key Host's master while a kept tab is out of view, waits for the shown tab to stream
  again, freezes herdr's server (as a slow link holds the attach), selects the kept tab and takes a strip. Red on the
  old code: 43141931169, 43143979785 and 43144753506 (the panel in every frame of the strip; the last two also saw
  the card in view say "stopped" once back, as did 43143166180). Green on the fix: 43143874306, and 43144916357 with
  FailureTests' and ReconnectTests' stream tests. Pictures: `~/Downloads/ovvi-research/p57s2/`.
- **For the user.** On a remote machine, leave a tab out of view, drop the link or sleep the Mac, come back and
  select it: its last picture, then the live terminal, never "The terminal stopped".
111. The Tart VM plugin (agent tart-take-control; screenshot `.build/fb57/r8-tart-6.50.02.png`): "so i noticed some
     permission prompt in tart vm, but i cannot click anything, and also i see in use lock on top, how this in use lock
     works? is it specific to our ovvi use case where we acuire lock or soemthing generic? just make sure its generic
     one and not specific to ovvi locks, also how can i accept such permission dialogs when we lock it". Then: "can we
     simplify those locks thing, even though its generic, its some custom locks, new agents will not be aware of it,
     we don't need all such locks, at least from plugin perspective, we can just show one toggle, watch only or not,
     when that button is sleected it wil be watch only, otherwise i can interact with it, lets keep it like that".

### Track R2 (items 104, 105)

- **Cause (104, windows).** Since macOS 15 a non-sandboxed app's saved windows live in talagentd's container,
  `~/Library/Daemon Containers/<uuid>/Data/Library/Saved Application State/<uuid>.savedState` (the uuid from
  `ApplicationMapping.plist` by signing identifier), which macOS guards: Full Disk Access only. The reset deleted
  `~/Library/Saved Application State` and `$TMPDIR` (where only `-ApplePersistenceIgnoreState` launches write), so
  the "fresh" launch restored the old windows, and a restored window starts and connects its pages.
- **Cause (104, the script).** Its rm loop ran in a pipe under `set -e`: the first path macOS refused (the WebKit
  helpers' `…/C/com.apple.WebKit.*+dev.ovvi.app`, "Operation not permitted") ended the loop, so `~/.config/ovvi`,
  the logs and `~/.local/state/ovvi` stayed (birth times on the user's Mac show it). Under `sudo`, HOME and the temp
  folders are root's: nothing matched, and it exited without a word.
- **Fix.** A first launch (no `welcomeDone`) closes the windows macOS restored before they show and restores no
  pages, so nothing connects and macOS forgets those windows; the welcome's end opens the new-window view. The script
  goes on past a refused path, lists what it kept with the Full Disk Access fix (exit 1), deletes the talagentd
  folder when it may (else says the app closes those windows), and refuses root. The stale `dev.ovvi.app.agents.*`
  domains are read by nothing. The e2e helper's `forget-windows` clears talagentd's folder too: it missed it, the
  likely cause of A2's "three windows of `one` right after `forget-windows`".
- **Fix (105).** The new-window view's Add Machine remembers its window; the added machine opens and connects there
  while that window is still open and empty, else in a new window as before.
- **Decisions.** No `ApplePersistenceIgnoreState` on a first launch: it writes that run's windows to `$TMPDIR` and
  leaves the old ones, which the next launch would restore. Notifications, the login item and privacy grants
  (macOS's own records) are not reset. An Add Machine cancelled in Settings leaves its empty window chosen: a later
  add from anywhere connects there while it stays empty. A window opened for a folder at a first launch closes too;
  the folder opens with the first window.
- **Runs.** CI 43144112186: both new tests' checks held (the welcome test then failed on a window screenshot of the
  panel, which XCUITest sees as no window), with the restore and welcome tests green. CI 43146598006: both green. No
  red run on the old code (the Mac's load); the reviewer traced both tests failing there: the restored window
  connects `one`, and Add opens a third window. Pictures: `~/Downloads/ovvi-research/p57r2/`.
- **For the user.** Quit Ovvi, run `scripts/reset-app-data.sh` (no sudo) from a terminal; it now says what it kept.
  Launch: only the welcome, no window, no connect; Skip or Get Started opens one new-window view. ⌘N ▸ Add Machine…
  ▸ Add: the machine connects in that ⌘N window.
112. "one more minor bug, clicking on pane header doesn't activate the pane, let's fix that please" (Track H2).

### Track T2 (item 111)

- **Finding.** The lock was generic (an `flock` on `~/.config/ovvi-tart/locks/<vm>.lock`, any tool, any VM), but a
  convention a tool had to know; the prompt could not be clicked because the card sent no input while
  `make vm-e2e` held it.
- **Fix.** The plugin knows no lock: no "In use", no `ovvi-tart in-use`, no bridge lock socket, and Open in Tart,
  Stop and Delete no longer refuse. One header toggle, **Watch Only** (an eye), on a VM's page: on, the card sends no
  pointer or key; off (the default), it does. The app keeps its value in the card's state. Plugin 0.7.0. The repo's
  own VM lock (`scripts/vm-test.sh`, agents' `lockf`) stays as it was, the repo's alone.
- **Runs.** Host only (round 8): `make lint build test` and the plugin's build. No UI test covers the plugin.

### Track L2 (items 100, 101)

- **⌘⌥-click (100).** A new opening, `Opening.mac`: ⌘⌥ alone shows a terminal link (tint, pointing hand, its
  accessibility title) as ⌘ and ⌥ do, and its click opens the link in the Mac's default app with `NSWorkspace`: a web
  address in the default browser, `mailto:` in Mail, another scheme (`ftp:`) in its app when the Mac has one, a file
  in its app, a folder in the Finder. A path is checked first ("File not found: ‹path›" when gone); a file on a remote
  machine, or a remote machine's own address (`localhost`), shows "‹path› is on ‹machine›, not on this Mac". An OSC 8
  link takes ⌘⌥ as it takes ⌥ (libghostty gets ⌘). `Links.open` stays the one router, for Track C4's chat links too.
  The link test now ⌘⌥-clicks a folder and finds its Finder window.
- **Cause, selection (101a).** Not Track L: `link-url = false` and the app's underline touch no color, and a pre-L
  build (`4942f142^`) selects as the current one does in the VM (sheets). Selections kept each cell's own text color
  (`selection-foreground = cell-foreground`), so a program's colors decided whether selected text shows. In the
  user's screenshot the selected text drew `#000000` on the dark blue, while pi's text around it was light; a shell's
  default, ANSI, 256-color, truecolor, bold, faint and reverse text did not repeat that in the VM, but a light truecolor
  text (a TUI's dark-theme color) vanished under the light blue.
- **Fix, selection.** Selected text takes the theme's text color, as Ghostty's own Alabaster (`#000000` on `#BFDBFE`)
  and Afterglow (`#D0D0D0` on `#303030`) themes do. Light takes Ghostty's Alabaster colors; dark keeps the blue
  `#1B3A58` under Afterglow's `#D0D0D0` (7.6 to 1): Ghostty's `#303030` is 1.1 to 1 over a dark card.
- **Fix, the link's look (101b, and the follow-up).** Before Track L, libghostty drew the hover underline at the
  font's underline position; Track L's own line sat 2 px higher, so over a TUI's underlined link two lines showed.
  An underline of any kind fights the text's own formatting, so the hovered link now gets a tint instead: one rounded
  box a row (the label color at 0.12, 4 pt corners, 2 pt past the ends), only the link under the pointer, with the
  pointing hand. It leaves a TUI's underline, colors and the selection as they are. Tried in the VM side by side, dark
  and light, over plain, underlined, colored, OSC 8 and selected text: Ghostty's underline (overlaps an SGR 4
  underline, so it adds nothing there), a grey tint (picked), an accent tint (gone over the blue selection) and an
  outline (reads as a button). Ghostty, iTerm2, VS Code's terminal and Warp underline on hover; they draw it as the
  cell's own underline attribute, which Ovvi's overlay cannot. An OSC 8 link keeps libghostty's hover underline: it
  gives no cell range to tint.
- **Text weight (101c).** Ovvi's libghostty config matches Ghostty's defaults for rendering: `font-thicken = false`
  (Ghostty's default; the package's old `true` went away in Track N), `alpha-blending = native`, 13 pt, sRGB. In the
  VM, Ghostty.app 1.4.0 and Ovvi with the same font (`.AppleSystemUIFontMonospaced`, SF Mono) put the same ink on the
  same line (12.6 % and 12.6 % of a cell row's area). The difference is the font: Ghostty's default font is the JetBrains
  Mono it carries (`ghostty +show-face`: "JetBrains Mono"), a heavier face (13.6 % on that line); Ovvi's default is SF
  Mono (Settings, Terminal, Font; design page Settings). The user's Ghostty also uses Nord Wave, whose text `#D8DEE9`
  is a step brighter than Afterglow's `#D0D0D0`. No change: JetBrains Mono, installed on the user's Mac, is in
  Settings' Font menu.
- **Runs.** VM: a scratch look scene (not committed) on `4942f142^` and on the fix, Glass and Classic, dark and
  light: text, ⌘ hover, selection; a second one with the four hover looks. Ghostty.app in the VM with SF Mono and
  with its defaults. CI 43147471618 (chosen
  tests, executed 3: the link test with its new ⌘⌥ steps, selected text, the floating link) green. The tint: CI 43151724862
  (the link and floating-link tests) green. Pictures:
  `~/Downloads/ovvi-research/p57l2/`.
- **For the user.** Select text in a pi or Claude Code pane, dark and light: one text color on the blue. Hold ⌘ over
  a link, also one a TUI underlines: a soft grey box behind it, no second line. ⌘⌥-click a web link (default browser), a file (its app) and a folder
  (Finder); on a remote card a file says it is on that machine.

### Track H2 (item 112)

- **Findings.** Cause: the background of a card's header (`PaneCard.header`) had only the double-click zoom and the
  drag source. A single click went nowhere. The content takes the keys by itself: the terminal view, web views and
  the chat's composer report it through `tookKeyboard`. Fix: a simultaneous `TapGesture` on that background calls
  `page.go(to:)`, the same path that ⌘] and the sidebar's rows use. It is simultaneous so the click doesn't wait out
  the double-click interval. This covers terminal, browser, plugin and chat cards, and the empty parts of the
  second row too (toolbar, plugin header, agent row). Buttons, the address and path fields and the rename field
  keep their own clicks. A drag starts an AppKit session, which takes the mouse-up, so a drag doesn't fire the tap.
  A double-click activates the card, then zooms it. A floated pane's placeholder is left alone: its body does
  nothing either, and only Show Window raises the window. Floating windows need no change: a click on the header
  makes the window key, and AppKit gives the keys back to that window's pane.
- **Runs.** New test `testAClickOnACardsHeaderGivesItTheKeyboard`. Red on the old code: CI 43149962436 ("the
  keyboard is on 'terminal.w2:p3'"). Green on the fix: CI 43149958677, 3 tests, together with
  `testCommandTOpensInTheKeyboardCardsDirectoryAndCommandWClosesIt` (double-click zoom on the header) and
  `testDropOnACardsCenterSwapsAndOnItsEdgePlacesBeside` (header drag). `make lint build test` green on the rebased
  tree. No pictures: nothing looks different.
- **For the user.** In a split, click the empty part of the other card's title row: it gets the border and takes
  typed keys. Drag the header to move it; double-click the header to zoom it.

### Track E2 (items 102, 103, 107)

- **102, Git.** "Commits in the history" now starts at 100 (was 500), and Show More reads as many again as the
  setting (100 more by default) instead of 500.
- **107, Markdown.** The pencil lock is a segmented control with words, **Read** | **Edit**, drawn like the mode's
  segments beside it (`pane.<card>.lock.read`, `.lock.edit`). ⌘E and the setting work as before.
- **103, the tree beside a file.** Row 2's old Show in File Explorer button is now **File Tree** (`sidebar.left`,
  at the left, after Back and Forward). It shows the tree inside the same card, at the left of File, Preview or
  Markdown. Each card has one tree (`side.ts`), outside the routed pages, so its open folders and its scroll stay
  while the card shows one file after another. It reuses the tree page's code (`files.ts`) unchanged, through a
  scoped `ovvi`: the header and ⌘F stay the file's, and a folder or `..` that the tree would open as the card's root
  roots the sidebar instead. A click selects; a double-click on a file shows it in the card. **Close File** (`xmark`,
  after the breadcrumbs) moves the card to the tree's page with the file selected. The setting "When a file opens"
  (Show only the file, Show the file with the tree) is the start; the card keeps the user's choice and the width
  (drag the edge, 140 pt to 60 %).
- **Decisions.** The sidebar's root is the root of the tree page the card came from, else the file's folder. Close
  File goes to the tree page, not to an empty card: "leaving the tree" is the tree page, and a double-click there
  opens the next file with the sidebar again. Markdown's outline toggle moved to `list.bullet.indent`, so the row does
  not show two `sidebar.left` icons. Close File sits after the breadcrumbs, as a tab's close button, away from the
  card's own close button above the row's right end. The hidden sidebar uses `visibility`, as the runtime's pages
  do, so it keeps its layout and scroll. No UI test sets the setting to "Show the file with the tree": it is one
  condition, and changing a plugin setting in the tests' shared config folder would reach other tests.
- **Review.** One blocker (the new test's iid had 7 characters, so its card stayed a terminal) and five shoulds
  (Close File under the card's close, the hidden tree losing its scroll, keys left on a hidden row, Show Hidden
  Files not reaching the sidebar, a check that could not fail), all fixed with most nits.
- **Cause (FileTests).** `testAFileCardEditsSavesAndReloadsItsFile` waited only until the pane did not show
  `printf`, which is also true before the shell echoes the line. On the slow VM the card opened before `git init`,
  so its breadcrumbs started at `/`. It now waits for an echoed marker.
- **Runs.** Tart VM: the new `testFileExplorerShowsTheTreeBesideAFile`, `testFileExplorerBrowsesOpensAndGoesBack`,
  `testMarkdownCardReadsEditsSavesAndLinks` and `testGitHomeInitializesCommitsAllAndShowsMore` green; there
  `testAFileCardEditsSavesAndReloadsItsFile` shows breadcrumbs from `/` (no repository found) also with the marker
  wait, and is green on CI. Chosen-tests CI 43150501629: 6 tests, 0 failures (the five above and the Preview test).
  `make lint build test`: HerdrKit's "a dropped follow stops its backlog" missed its bound twice at a load over 150,
  green on the rerun. Pictures: the VM, dark and light, before and after (no before picture of Git: the old card
  never finished loading in the VM).
- **For the user.** Open a file from the tree, press File Tree, browse (go up with `..`, open folders with the
  chevron or →), double-click files, collapse it, drag its edge, and press Close File. Set Settings ▸ Plugins ▸
  File Explorer ▸ "When a file opens" to "Show the file with the tree" on a new card. Check Markdown's Read | Edit
  in dark and light, and Git's Show More on a long history.

### Track C3 (items 106, 109)

- **106, the look.** An empty chat puts the agent's glyph (34 pt, gray) beside a phrase (26 pt semibold, one line,
  shrinks to fit a narrow card) and the reply box together in the middle of the card. The phrase is one of five, picked
  when the chat view is made: "What's on your mind?", "What are we building?", "Where should we start?", "What can I
  help with?", "Ready when you are."
- **106, the motion.** On the first send the header fades, the box goes down to the bottom and the message rises from
  the middle to the top: one 0.22 s motion (`Animation.slide`), none with Reduce Motion. The box keeps one identity (a
  `maxHeight` frame centers it), so it keeps the keyboard. An offset transition on the new scroll view moved nothing
  (only its fade ran): the rise is a keyframe offset on the content, keyed to the empty state. The card's height is
  kept unobserved, so a resize builds no rows. CI runs with Reduce Motion: only the VM strips check the motion.
- **Decisions.** A chat shorter than the view now sits at the top (`defaultScrollAnchor(.top, for: .alignment)`; the
  first offset and size changes keep `.bottom`), so the first message goes up, as the user described. While a history
  loads into an empty chat, a spinner takes the header's place and the box stays in the middle: a load that ends empty
  (a new Codex or OpenCode chat) moves nothing. A sent message stays while the transcript it starts loads: the old
  spinner took the risen message away for a moment (seen in the CI strips of 43149628284). The first switch to Chat on
  an existing session can show the header for the one follow before its load starts; gating it on `current` would hold
  an agent started in its TUI (a Claude Code with no transcript before its first message) on the TUI for 2 s.
- **109, cause.** The header's state label took the chat's phase: pi writes `idle` when its turn settles, but while it
  waits on agents or background jobs herdr hears working, which the TUI's header shows. While the chat is ready, the
  label now shows herdr's state, as the TUI does; Send, Stop and Esc still go by the chat's phase (an idle pi gets no
  Esc). Floating panes use the same label.
- **VM.** `scripts/vm-test.sh` puts the agents' stand-ins on the guest's login shell PATH, as ci.yml does: the chooser
  showed every agent as "Not installed" in the VM, so no chat test could start there.
- **Runs.** Exploration on CI while the VM was busy (43143732838: the offset transition did not move; 43145170453:
  the keyframe rise works, pi's Working holds). VM: the look and the first send, wide, narrow and floating, dark and
  light, green. Pictures: `~/Downloads/ovvi-research/p57c3/`.
- **For the user.** The first send in a new chat, wide, narrow and floating, dark and light; a pi that waits on agents
  shows Working in Chat as in the TUI; a long reply or a history coming into a new chat ends on its last row; a split
  down under a short chat whose rows then pass the card shows its top with no Scroll to Bottom until the next message
  (open).
- **Follow-up, cause.** The `.top` alignment anchor sets a short chat at the top, and the bottom anchor holds only a
  chat at its exact bottom: a chat that passed the view from short (the sent message, then a 25-turn transcript; any
  chat whose turns pass the view) stayed at its top, not on "Last.". Every test that sends `many` into an empty chat
  failed on CI (4 of 4); in the VM 1 run in 2, as its transcript came in parts there.
- **Follow-up, fix.** Under the rows the stack has a blank as tall as the scroll view's container (its height from
  the scroll geometry, observed only by the blank, so a resize builds no rows). A short chat's rows still sit at the
  top, and the chat is at its exact bottom, so SwiftUI's bottom anchor follows its rows as they pass the view, and a
  reply box that grows or a card that shrinks under them. The anchors and the first-send rise are as C3 made them:
  the container's height holds still while the reply box goes down, so the offset stays 0 (VM log and strip).
- **Follow-up, tried.** A blank of `containerRelativeFrame`'s height: it switched between the view's height and that
  less the reply box's inset at each frame of the rise, and the scroll bar showed. One scroll to the end from the
  scroll-geometry action when the end left the view: a `ScrollViewReader` scroll asked for in the update where the
  rows grew used the end's old place and moved nothing when a whole history came in one read (CI's log), and on the
  next turn it was still racy (CI and the VM each failed one test).
- **Follow-up, open.** A split down under a short chat that then passes the view: the geometry reports the bottom, but
  the card shows the top until the next message, which follows. C3's code showed the top there too.
- **Follow-up, runs.** Red on main 559fce8c: CI 43160568640 (`testALongChatShowsEarlierRowsInPlace`,
  `testSwitchesKeepHeavyCardsAsTheyWere`, `testALongChatKeepsItsPlaceAndScrollsToTheBottom`,
  `testTheChatsEndMovesWithTheFingers`; the other 12 chosen chat tests green). Red on the two scroll-to-end tries:
  43163314751, 43165274094, 43166901269. Green: the VM (those four, the question, reply-box, floating and tool tests,
  probes for the first send, a box grown and a split) and CI 43168893975. Pictures: `~/Downloads/ovvi-research/p57c3b/`.

### Track C4 (item 110)

- **Cause.** The chat linked only `http`, `https` and `www.` addresses (`NSDataDetector`), drew them in the accent
  with no underline, and opened only web pages, on a plain click, ⌘ or ⌥. No paths, no `:line`, no ⌘⌥.
- **Fix.** The chat finds links with the terminal's `TerminalLink`, one line at a time, in the user's messages, the
  replies, inline code, code blocks and a tool call's Input and Output (`ChatLinks`), and opens them with the
  terminal's `Links.open` and `linkKey`, so ⌘-, ⌥- and ⌘⌥-click (L2's `.mac`) match the terminal. A found link rides in
  SwiftUI's `.link` as JSON under `ovvi-chat-link:`. Links are underlined in the accent (white in the user's bubble);
  under the pointer they turn 70 % and the pointer is the pointing hand. Text is 14 pt on 20 pt lines (was 17.2).
- **Decisions.** A plain click opens as a browser's link does, in a new tab, selected (`Links.open` passes
  `background: how != .here`); ⇧- and ⌃-click stay the text's. A Markdown `[label](…)` opens only `http`, `https` or
  `mailto` (its label hides the target). `www.example.com` is no longer a link, as in the terminal. An edit's diff has
  no links. A text with more than 100 links shows them without the hover (each link nests the joined `Text` a level
  deeper: the reviewer's probe overflowed the stack at 750).
- **Hover, what held.** Selectable text puts its I-beam over a SwiftUI `pointerStyle` and over `NSCursor.set()`, so a
  clear area over each link takes the pointer and the click; SwiftUI then sends no hover (neither on the areas nor on
  the text), so an AppKit tracking area (hit-test nil) tells the link. The 70 % is a `TextRenderer`: a changed
  attribute lays the text out again and cleared a selection. Checked in the VM, frame by frame (hand cursor, the
  lighter link, the selection kept).
- **Runs.** Chosen tests on CI: 43151059879 (before pictures), 43151068571 (after; the link test failed on its own
  prompt: a message that starts with `/` is a command, for the TUI), 43157037400 (the chat, long-chat and switch tests:
  13 of 15 green). Its two reds, `testALongChatShowsEarlierRowsInPlace` and `testSwitchesKeepHeavyCardsAsTheyWere`,
  fail on main 3a547d91 in the VM too (1 of 2 runs): after the first send into an empty chat, a 25-turn history stays
  at the top (C3's `.top` alignment anchor), not on "Last.". VM: the link test green on the final code, the pictures.
  Pictures: `~/Downloads/ovvi-research/p57c4/`.
- **For the user.** Hover a link and a path in a reply and in a tool's Output (the hand, the lighter link); ⌘-, ⌥-,
  ⌘⌥- and plain click on a path with `:line`; select text, then hover a link; the new line height in long replies,
  lists and code blocks.

### Round 8, second batch (items 113–119)

113. "sometimes i see white cursor block kinda thing when selecting, why is that? can we fix that"
     (`.build/fb57/r8-cursor-11.33.22.png`; Track L3).
114. "can we make jetbrains mono as the default font? curious why sf mono was chosen as default? also check these 3
     screenshots ... in each one the left most has ovvi with font set as shown in setting window, then you have one
     ghostty window with pi logo being visible and then you see browser pane with pi logo, check which fonts come close
     to original pi logo, i think fira code, jetbrains mono seems slightly taller, make jetbrains mono as default for
     now, just give me your analysis on all these fonts though. and also search internet on some of the popular fonts
     people use in terminals, modern, good quality and popular ones which are open source, from these analysis we can
     take a call what to keep the default one and what other fonts to support in our settings etc"
     (`.build/fb57/r8-11.39.08.png`, `r8-11.39.18.png`, `r8-11.39.26.png`; Track L3).
     After the report (`~/Downloads/ovvi-research/p57l3/fonts.html`): "on the terminal fonts report, makes sense,
     let's make jetbrains mono as default and leave existing list of font options". So no fonts are bundled.
115. "in file tree sidebar, text is getting clipped, can we do some ellipsis kinda thing or what vscode does"
     (`.build/fb57/r8-11.49.57.png`; Track E3).
116. "also from file explorer when i open certain file with sidebar disabled by default, the file opens and when i open
     the tree, the file tree rerenders and opens up the folder, even when you normally open, keep the file tree state as
     is and open the file within that, probably we are doing a fresh page load, basically keep the entire file explorer
     like a single page app, with all state present, so file tree stuff doesn't seem liek rerendering and stuff"
     (Track E3).
117. "instead of showing blue colored icon when sidebar is opened, can we use sidebar open and close icons, like i
     think there are two sidebar icons showing the state right" (`.build/fb57/r8-sidebar-icon-11.59.07.png`; Track E3).
118. "word wrap should be disabled by default in file editor" (Track E3).
119. "for markdown outline icon, let's move it to top right where other markdownbuttons are" (Track E3).

### Track E3 (items 115–119)

- **Cause (115).** Pierre's tree cuts a long name in the middle: the stem with a "…" marker laid over its end, the
  extension kept whole. The marker hides the letters under it with the row's own background, and our rows are clear
  (`--truncate-marker-background-color: transparent`, so Glass's card shows through): the "…" and the letters below it
  both drew ("AgentCard:swift").
- **Fix (115).** The name is one line cut at its end, as in VS Code: CSS over Pierre's truncate markup in the trees'
  shadow roots (its wrappers `display: contents`, its marker and its hidden copy gone), so the text ends in
  `text-overflow: ellipsis`. A cut name gets its whole name as a tooltip, set on pointer moves only while it is cut. The
  tree's page, the tree beside a file, the filter's matches and the sticky folders all use the same rows.
- **Cause (116).** The card had two trees: the tree's page (a routed page per root) and the tree beside a file
  (side.ts, its own tree). The first File Tree after opening a file drew a new tree and opened the file's folders one
  by one, and folders opened in one never showed in the other. No page load was involved: the runtime keeps pages.
- **Fix (116).** side.ts owns the card's trees, outside the routed pages, one per root (the last five, as the runtime
  keeps pages). The tree's page is now an empty routed page: the same tree lays out over the whole card while it shows
  (CSS on the shown page), and at the left beside a file. Row 2's controls and ⌘F of the page reach the tree; on the
  page the tree's moves move the card, beside a file they root the side only. A tree of a new root draws hidden and
  shows once it has its rows, and only if the card is still there. Hidden trees hold their watch calls, as kept pages
  do.
- **Fix (117–119).** A manifest toggle may name an `onSymbol`: that symbol while on, in the buttons' color, with no
  accent. File Tree is `sidebar.left` hidden and `rectangle.leadingthird.inset.filled` shown (same size, so the button
  does not move). Word Wrap starts off; its toggle stays. The outline toggle moved to the right group, before Rich Text
  | Source and Read | Edit. Explorer 1.12.0.
- **Decisions.** End ellipsis, as VS Code, not Pierre's middle cut (it keeps the extension, but needs an opaque row,
  which Glass does not have). The tooltip only for a cut name, as the Finder does. Back to an older root shows its kept
  tree as left, up to five roots. The pair of symbols follows VS Code's on and off layout icons; macOS's own sidebar
  buttons use one symbol for both states.
- **Review.** One blocker (a new root's tree switched in as its page started to draw: an empty tree under the old row
  2) and two shoulds (rooting the side lost the file's selection; the new test's scroll could not tell old code from
  new). All fixed, with most nits.
- **Runs.** Chosen-tests CI 43188424253 on the reviewed head: 11 tests, 0 failures (the new
  `testFileExplorerKeepsOneTreeForItsPageAndItsFiles`, every FilesTests and FinderTests explorer test, Markdown, File,
  Preview and HTML). On the old code the new test fails twice over: the side is a fresh tree (no `out.o`, a different
  scroll) and a folder opened beside the file is closed on the page. The Tart VM: the new test, File Tree beside a file,
  Find and Markdown green; FileTests' crumbs start at `/` there (known, green on CI); a macOS "Dock Tile Extension
  Added" banner in the VM took one float click (System Settings opened). Pictures from the VM, before and after, dark
  and light. `make lint build test` green on the rebased tree.
- **For the user.** Open a file from the tree, then File Tree: the same folders open, at the same scroll, no
  animation. Open folders beside the file, press Close File: the page shows them open. Hover a cut name for its
  tooltip. Check File Tree's two icons, Word Wrap off on a new card, and Markdown's outline toggle at the right, in dark
  and light.

### Final CI, round 8

- **Cause (Recent after the sort menu).** In Recent the sidebar holds the rows' order while the pointer is over the
  list. The hold was taken whenever the pointer entered the list, also in Manual (herdr's order), and a switch to
  Recent kept it. The menu's Recent item lies over the list, so the pointer came back within the hold's 1 s clear and
  the rows kept Manual's order until it left: run 43171081544 picked Recent (teardown read "Recent") and showed alpha
  above beta for 20 s with the pointer resting on alpha's row. Timing decided it: the same test passed in 43171070157.
- **Fix.** A change of the sort takes the hold again in the new order, so a pick shows at once and agents' changes
  still hold still under the pointer. The test hovers a row before it opens the menu, to take the Manual hold.
- **Runs.** CI 43179476920 on the fix (the Recent test, agents by tab and place, the pointer after pins), green. The
  old code with the sharper test passed too (43179470745): no cheap repro, as XCUITest opens the menu only by a click
  that leaves the list.

- **Cause (⌥-click on a chat link), unproven.** In 43171070157 the ⌥-click landed on the reply's link, where the green
  ⌘-click had landed, 0.7 s after the switch back to the chat's tab; the app worked 2 s on it (1.2 s in the green
  run) and opened nothing: no split, notice or tab. The step's wait was blind (the hidden, kept page has the reply
  too), and ⌥ went down with the pointer still on the tab bar. A VM probe showed only the green path (tap, ⌥, side,
  split). Best guess: the re-show's focus and redraw ate the tap.
- **Fix.** The step waits for the shown page's reply box to take the keys, then hovers the link before ⌥, as the ⌘
  step does. The chat reads a link click's keys from the click, not from the keys held when it runs late.
- **Runs.** Red: full run 43171070157 (shard 3). The VM green before and after; CI 43181605437 (chosen, executed 1)
  green. Two full runs in a row green prove it.

### Round 8, chat review (items 120–125)

120. "let's keep the logo to the center like before and put text below it, it doesn't look good when beside"
     (Track C5).
121. "links are looking weird with grey background, that grey background thing looks good on the terminal view, in
     chat view why do you need that grey background, show like how links are shown in browser like the default html
     view and hover" (Track C5).
122. "in general not just chat view, option+click takes some time before the pane shows up while cmd+click and
     cmd+option+click, why is that? is there any bug with option+click? check if we can improve that, make
     option+click as well instant" (Track L4).
123. "when a chat is resumeed, or used relaunch with chat, while the transcript loads or something, i see the new chat
     view showing text and input in center and after few seconds then the trnascript loads, can we show loader instead
     during that time, its confusing seeing new chat view when relaunching existing chat" (Track C5).
124. "so we show working x seconds and then change to worked x seconds once done right, but this showing worked x
     seconds its not consistent, it shows sometime, it doesn't show sometime, do we have any logic on when its shown
     etc? can we keep it consistent? just show it all the time when assistant conversation is ended, and keep that as
     is even if there are further messages, basically user message -> tool calls + intermediate assistant messages +
     more tool calls + final assisant message -> worked x s -> new user message -> asssistant messages -> worked y s ->
     and so on, keep it consistent like this, its bit buggy right now, make sure this flow works well" (Track C5).
125. "clean up chat view code better and make it simple and clean we shouldn't have too many edge cases handling, it
     should be clean, simple following ponytail principles, and work reliably" (Track C5).
126. "one more thing, let's say a pane is in chat view, and leave it for sometime, and go to other tabs and work on
     other tabs, idk when exactly may be open amny panes or soemthing, then come back to this chat pane, for a very
     brief second you see tui and then it shifts to chat view, it doesn't happen for recentyl viewed chat view, like i
     see it happens only some time, make it reliable, i think we rerender or something and that's causing this
     transient bug, figure it out and fix it" (Track C5). Then: "yeah i see the pattern, just open like 10 browser
     panes, go to each of its tab and make it active, then come back to the chat view you see the tui for a breif
     milliseconds".
127. "okay one more thing, in browser or in file explorer, i don't see option to make vidoes full screen, can we
     enable that? so i can easily open and watch videos in full screen" (Track V2).

### Track L3 (items 113, 114)

- **Cause, the white block (113).** Not the cursor: pi's own text selection. pi's full-screen mode reads the mouse and
  draws a selection in reverse video, covering both end cells. Ovvi sent every left drag to libghostty (the card's
  selection) and through herdr's `terminal.mouse` to the program, so two selections drew. herdr flattens reverse video
  of default colors to `#000000` on `#FFFFFF` (spiked), so where pi's ends and libghostty's (a cell counts past 60 % of
  its width, Ghostty's rule) differ by a cell, a pure white cell showed beside the blue. pi's editor caret is the same
  reverse video, so it is white too where Ghostty draws it in the theme's text color: herdr's flattening, left as is.
- **Fix.** Ghostty sends a drag to a program that reads the mouse and selects locally on ⇧-drag; herdr 0.9.5 reports no
  mouse mode (not in frames, the schema or the snapshot), so Ovvi cannot follow that rule. A left drag, a double and a
  triple click are the card's; a program gets a single left click when the button comes up on the cell where it went
  down. A program gets no left drags now (vim's mouse selection, a scroll bar's thumb): `ponytail:` note, upgrade once
  herdr reports the mode. The right and middle buttons are unchanged.
- **Why SF Mono (114).** The first design ("Terminal text is SF Mono / Menlo", the reference app's native look); phase 11
  set `monospacedSystemFont` as the default over libghostty's own JetBrains Mono, and no decision revisited it.
- **Fix, the default.** An unset `font-family`: libghostty carries JetBrains Mono 2.304 (Ghostty's `font/embedded.zig`,
  its name strings are in `libghostty.a`). In the VM, with no font installed, an unset font and `font-family =
  JetBrains Mono` both draw it. The menu lists JetBrains Mono, SF Mono (by the name CoreText resolves on every Mac),
  then the installed families. Acknowledgements list the font (OFL). Symbols Nerd Font, also inside libghostty, is
  still not listed.
- **The logo.** pi's logo is 4 cells by 2 rows of half blocks, which libghostty draws itself to fill the cell, so only the
  cell's shape matters: square when the height is twice the width. Measured in the user's shots: Fira Code 64 × 64 px
  (square), SF Mono 64 × 62 (3 % flat), JetBrains Mono and Ghostty.app 64 × 68 (6 % tall). The height is ascent +
  descent + line gap (OS/2 typo metrics with USE_TYPO_METRICS, else hhea). Report with 17 fonts, popularity (GitHub
  stars, Homebrew installs) and VM renders: `~/Downloads/ovvi-research/p57l3/fonts.html`.
- **Decisions.** pi no longer gets drags, so its own selection's scroll past the card's rows and its limit to one
  scroll box are gone: a long selection ends at the card's edge. Two quick single clicks that pi counts as a double
  click can still make it select a word (rare, accepted). The settings test picks Menlo, not Monaco: Monaco and JetBrains Mono have the same 8 × 17 cell at 1x
  on CI. CI's grids change with the font (17 px rows instead of 15 at 1x).
- **Runs.** CI 43184328997 (chosen: the ⌥-right/left click and drag steps, the font and Option key test, selected
  text). On the old code (reasoned, not run) the new steps fail: the drag's press and release reach `cat -v` before
  the ⌥-right click.
- **For the user.** In a pi pane, drag over text and double-click a word: only the blue selection, no white cell. Click
  a link and a tool block in pi: they still open. Settings ▸ Terminal ▸ Font: JetBrains Mono first, SF Mono second; the
  text looks like Ghostty.app's. A selection in pi now stops at the card's edge. Your own `terminalFont` is
  "JetBrains Mono" (the installed copy), so the menu lists it twice: pick the first, or quit Ovvi and run
  `defaults delete dev.ovvi.app terminalFont`. Read `fonts.html` and pick the font list.
128. "in chat view one more thing, before when the message is in stil waiting to be sent like its waiting in queue
     etc, message used to be shown bit less opacity or dimmed, and that changes to correct color once it submits, now i
     don't see that, let's bring that back too" (Track C5).
129. "yo one more improvement to chat view new chat state, i konw we do show now random greeting, but the placeholder
     remains same ask anything, can we change the placeholder as well dynamically relevant to the greeeting message, so
     essentially we have tuples of greeting and its placeholder and we show that accoridngly" (Track C5).
130. "one more improvement in new pane, when new pane is opened we can select by numbers, but also can we change
     selection based on what i type for example, i type pi then pi will be selected, we don't ened to show what i type
     anywhere, and we reset whatever typed with a short timer, like 1s or something, if i type file then fle explorer
     should be selected, essentially you highlight on the relevant ones based on what i type yk, it won't open it will
     just select it, does that makes sense" (Track N3).
