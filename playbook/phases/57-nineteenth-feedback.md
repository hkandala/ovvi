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
- **herdr is right.** Spiked with a real Meta `claude` (2.1.312, isolated `CLAUDE_CONFIG_DIR`, herdr's session hook)
  and `codex` (isolated `CODEX_HOME`) in `ovvi-dev-p57g`: after the quit the shell is in front and `pane.get` has no
  agent, also with a reported session.
- **Cause: the 10 s ran out.** It held a fixed 2 s wait, each herdr call (one process each: about 1 s apiece at a load
  of 300, 0.1 s at a calm one) and the agent's own exit. Meta's Claude Code is now a launcher with the native binary
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

### Track G findings, round 5 (item 44)

- **Spiked on plain installs** (npm into `/tmp`, an isolated `ZDOTDIR` shell with each agent's store in `/tmp`, in
  `ovvi-dev-p57g`): npm's pi sets `process.title`, and on macOS libuv writes the title over the argv area. herdr's
  `pane.process_info` then lists `name: node, argv0: pi` and no argv (`node -e 'process.title="pi"'` and `ps -o args`
  show the same). Ovvi found a chat only by the marker in the argv, so the card stayed a TUI with Relaunch with Chat.
  Claude Code before its native build did the same. npm's Claude Code 2.1.319 is now native (`claude.exe`, argv kept),
  Codex's npm wrapper has a native child with the argv, OpenCode is native with the argv. Meta's launchers keep the
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

## Track H: redraw a terminal's TUI (item 8)

8. "one more feature i wanted, is to have a shortcut to refresh tui, what i mean is sometimes agent inputs will become
   like this: <screenshot 5.18.41> if they are left idle or after sleep etc. and fix to this is to resize the window by
   either adding a new pane etc so the tui rerenders and those errors goes away, similar to cmd+shift+r which replaces
   the pane, we should have some way to rerender the tui, this should apply only for terminal panes not for others,
   figure out what shorcut would fit well, and see if we can do this rerender with that shortcut easily, should be
   there in cmd+k as well"
   - Also find what writes the `kq_dispatch` lines into the pane.

### Track H findings

- **Who writes `kq_dispatch`.** Meta's launcher binaries, not herdr (clean), libghostty or the agents' own code:
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
  keeps your terminals, panes and agents running.", over the install command, now a quieter tertiary line under it.

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
  Text keeps its 28 pt page margin. In a pane the same pages now start 9 pt under Back (they had 11 to 17); Back
  has 5 pt above it there, under row 1.
- **Fix, item 40, chat.** A bubble had 8 pt above its text and under its time: 23 and 22 px to the letters at 2x, 38
  px at the sides. 16 pt now: 39, 38, 38 and 38 px.
- **Runs, round 4.** Chosen tests 42557814388: 5 of 6 green, the floated browser's page gap read 11 vs 12 pt on CI's
  1x screen (the card's frame rounds; now 1 pt of slack); 42559159986 green (5 tests: browser, Git card and home, File
  Explorer's floated `..` row, floating chat).
- **For the user, round 4.** Panes changed too: plugin pages start 9 pt under row 2's Back there (were 11 to 17 pt,
  different per plugin). Markdown's Rich Text keeps its 28 pt page margin. Chat bubbles are taller (16 pt above the
  text and under the time).

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
