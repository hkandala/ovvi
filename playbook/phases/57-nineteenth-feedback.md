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

## Findings

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
- **Decisions, item 16.** 6 pt above a floated browser's toolbar and a plugin's row 2; pane cards unchanged.
- **For the user.** In a Git diff, ⇧] and ⇧[ jump by file (not ⇧⌘] ⇧⌘[, which switch tabs). Try ⌃- and ⌃⇧- in File
  Explorer and Git against your other apps. ⌘A in a locked Source view with its preview shown selects the preview too;
  ⌘C still copies the source.
