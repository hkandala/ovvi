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
