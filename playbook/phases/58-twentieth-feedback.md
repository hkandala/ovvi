# Phase 58: Twentieth feedback: clicks that always land, balanced splits, a smoother chat

Goal: the fixes from the user's twentieth round (round 9 after phase 57's eight):

- A click anywhere on a card gives it the keyboard, for every kind of card.
- Splits stay balanced as panes open and close (a setting, on by default).
- A program's own copy on select works again.
- The chat moves smoothly: no flicker, fades instead of jumps, tables without artifacts.
- Small fixes to onboarding, windows, settings, the explorer and links.

The user's words are quoted; the decisions under them are the orchestrator's. Screenshots in `.build/fb57/` (not
committed; JPEG copies in `~/Downloads/ovvi-research/fb/`):

| File | Shows |
|---|---|
| `r9-2.07.24.png` | a remote File Explorer showing "Can't list /home/hkandala/swebench-autopilot/learnings" |
| `r9-2.33.00.png`, `r9-2.33.03.png` | a chat table's header row while scrolling sideways: a rounded-corner fill in a cell |
| `r9-2.33.42.png` | a chat table's row cut off at the bottom ("in MiniWorld and Habitat" clipped) |

Tracks run in parallel and push straight to main after their review, `make lint build test` and the UI tests they
touch in the Tart VM (no per-track CI, no host GUI; `~/Downloads/ovvi-research/p58-common.md`). The phase ends with
two full runs and on-demand on the final head.

## Track A: onboarding, windows, settings (items 1, 2, 4, 5, 6, 21)

1. "during onboaridng if herdr is installed don't show the herdr slide at all, i see it worked fine before, but this
   time i saw the herdr slide where as soon as i moved to it, it showed herdr is installed? just make sure no
   flakiness is there in it"
2. "when starting session we show the power button icon, can we have some other icon? power button icon doesn't fit
   well"
4. "new window size should remember previous size, like when i open new window resized to certain size and position
   and when i open another new window it should follow same sizing and position"
5. "for font selection why there is a line separator? just list all fonts in alphabetic order and choose jetbrains
   mono as default"
6. "when installing new plugins, show in new pane should be unchecked by default"
21. "also one more thing i noticed, can we open floating panes in the same monitor as where it si coming from, like i
    connected to multiple monitors and i see when ovvi is on monitor 1 and from pi agent i opened a subagent in
    floating pane, it opened in the macbook, it should open in the monitor 1 where ovvi is"

Also: `scripts/herdr-session.sh` `down` and `up` wait 5 s (50 × 0.1 s), a bound that only matters when something
fails; lessons.md's rule makes it 60 s (round 8's final CI, '### Final CI, round 8' in phase 57).

## Track K: a click always activates the card (item 3)

3. "when plugin pane has some error, i saw some error saying nodejs not installed, while that's not the bug, but when
   such error comes, i cannot click on the pane to activate, clicking on header works, but clicking near the error
   doesn't activate the pane, also why this is such a common issue with activating panes, i have told these kind of
   bugs so many times already, investigate how clicking on pane activates and make sure it works all the time for
   terminal panes or browwser panes or plugin panes without any edge cases like this"

### Track K: Findings

- **How a click activated a card.** A card became the keyboard card only when a view inside it became first responder
  and claimed it: the terminal surface, a web view (`onKeyboard`), the address, path and reply fields
  (`tookKeyboard`). On top of that sat per-view tap gestures: the header's (phase 57 item 112), the browser cover's,
  the chooser's background. A view that takes no keys and had no gesture did nothing: a plugin's error
  (`PluginFailure`, the user's "needs Node.js"), a missing plugin, the plugin loader, a card's picture, a header
  button of a plugin. Each earlier report got a gesture on the one view it named, which is why the bug came back.
  Not a regression: `PluginFailure` never had one.
- **Fix: one mechanism.** Every card is its own `MovingCard` NSView. One local left-mouse-down monitor
  (`MovingCard.activateOnClick`) hit-tests the window, finds the card under the click, and on the next turn, after
  AppKit's mouse-down: if the first responder is inside the card (a field, the page, the terminal, selected text) it
  only marks the card (`tookKeyboard`); else `page.go(to:)` gives the keys to the card's own view. It never eats the
  click: links, buttons, text selection and drags work as before. The three tap gestures are gone. Skipped: a hidden
  or kept page's cards (`isHidden`), a floated pane's placeholder, an open panel, a window under a sheet.
- **A card with no view for the keys** (a missing plugin) left them on the old terminal while it showed the border:
  `PaneViewRegistry.focus` now clears the window's first responder then, so ⌘W and typing no longer reach the old
  card. A floating window whose first responder is the window itself gets its pane's view back on a click.
- A headless probe (an unshown window, `sendEvent`): `NSHostingView` refuses first responder, a click on SwiftUI
  content leaves it alone, and selectable text is an `AppKitTextInteractionView` inside the card.
- **A short card's error ran over its header** (seen in the VM; the orchestrator's follow-up). Cause: `EmptyState`
  has a fixed natural height, and SwiftUI centers a view taller than its frame on that frame, so it and the
  failure's solid fill ran up over the card's header rows. Fix: `EmptyState` picks its full look, else its compact
  look, else the compact look in a scroll view (`ViewThatFits`, the `scrollsWhenShort()` extension); the plugin's
  install question and the browser's "Open this page?" scroll the same way. Clipping the card's content area in
  `PaneCard` was the other place, but it would cut the chat's and the toasts' glass and hide the error's buttons.

### Track K: Runs

- New test `testAClickAnywhereOnACardGivesItTheKeyboard` (CardClickTests.swift): a terminal, a browser, a plugin
  page, a plugin error and a missing plugin in one tab, the address field and a plugin header button of inactive
  cards, a chat's reply and a drag-select on an inactive chat. Red on the old code in the VM: "w2:p5 is not lit" at
  the error step. Green in the VM with the fix, 8 tests: it, `testAClickOnACardsHeaderGivesItTheKeyboard`,
  `testAClickBeforeACardDrewKeepsTheKeyboard`, `testABrowserKeepsAFailedAddressAndTakesClicksOffItsPage`,
  `testDropOnACardsCenterSwapsAndOnItsEdgePlacesBeside`,
  `testCommandTOpensInTheKeyboardCardsDirectoryAndCommandWClosesIt`,
  `testFloatingAPaneOpensItsWindowAndDetachPutsItBack`, `testAChatTakesTheKeyboardOnAnyClickAndItsBoxGrows`.
- On the final tree (a drag-select step added): `make lint build test` green; in the VM green, 3 tests: it,
  `testAChatTakesTheKeyboardOnAnyClickAndItsBoxGrows`, `testAFloatingWindowShowsTheChat`. For the final round:
  FloatTests, BrowserTests, BrowserClickTests, PaneTests, FinishTests, PluginAPITests, the chooser tests.
- Pictures (VM, dark): `~/Downloads/ovvi-research/p58k/before-cards-to-click.png`, `after-error-clicked.png` (the
  error card lit, the terminal's cursor hollow).
- Reviewer: two rounds (a blocker on the missing plugin's keys, fixed), ready.
- The short card's error: the new check in the same test (the title stays at least 32 pt under the 70 pt header) was
  red on the old code in the VM ("639.75 is not greater than 653.5"), green with the fix, 6 tests: it,
  `testABrowserKeepsAFailedAddressAndTakesClicksOffItsPage`, `testAPluginPackageAsksForTrustBuildsAndReloads`,
  `testAPluginCardAsksAndItsPageSetsItsSettings`, `testTheOvviCommandListsAndInstallsPlugins`,
  `testAPaneLabeledInHerdrShowsItsPageAfterARestart`. Picture: `~/Downloads/ovvi-research/p58k/after-short-error.png`.
  Reviewer: two rounds, approve. The VM's saved main window frame was tiled to its left half (512 pt, from another
  run), which hid the second tab capsule and failed every `newTab`: deleted `NSWindow Frame main-AppWindow-1`.

## Track P: the overview's zoom, balanced splits (items 7, 8)

7. "i don't see any animation now when selecting a tab from overview, before i used to see some animation of pane
   zooming in and sidebar and tabs fading in, now its immediate without any animation, why it got removed?"
8. "when a pane is opened on side can we do auto resize automatically to balance like how we do when new side pane is
   opeened? also when a pane is closed as well do auto resize, so they are equal in size, basically apply auto resize
   all the time when panes are opened or closed, we can keep this is settings may be whether to auto resize or not,
   defaulting to auto resize, and if disabled, all auto resize should be disabled and should work like herdr tui
   splits where it goes half and half evry split"

## Track M: a program's own copy on select (item 9)

9. "now with our custom select or something i guess, copying text on pi agent is not copying text, if i choose option
   of copy on select from settings, it does select but loses formatting, that is okay with the settings, basically
   when you select normally on any tui its native copy on select should be invoked, coz pi agent pastes the well
   formatted text into the clipboard when i select, so make sure that works, that used to work fine before your white
   block fix i guess"

   Phase 57 item 113 (Track L3) made left drags the card's, because herdr 0.9.5 reports no mouse mode; the white block
   was pi's reverse-video selection drawn beside the card's. Both must hold: pi's own selection and copy work, and no
   white block.

   herdr drops the program's mouse mode (`MouseCapture`) in its CLI bridge, so Ovvi can't follow Ghostty's rule without
   an upstream change (patch: `~/Downloads/ovvi-research/p58m/herdr-mouse-mode.patch`). Asked about the options: "revert
   the fix, and figure is there a better way to fix that white block issue when selecting without removing the native
   drag".

## Track C: a smoother chat (items 10, 11, 12, 13, 15, 16, 22)

10. "on new chat, let's move it bit up such that propmt input is vertically center aligned, right now with logo and
    text it feels bit off"
11. "in the chat when long chat is loaded, i know we show loader and load it, but when transcript is revealed can we
    fade it in isntead of suddenly? like even if i switch between chat and tui quickly, i see transcript goes away and
    comes back like a flicker, let's either fix the flicker or add fade in animation so it doesn't look abrupt,
    similar animation when swithcing from low opactity to full opacity when prompt is submitted, it is bit abrupt now
    as soon as i submit prompt, i see bit dimmed version and then suddenyl changes, overall make the chat transcript
    smoother"
12. "make the prompt input bit more less transparent, like right now when i scroll, i see almost transparent and make
    typing propmt there harder, increase the opaqueness a bit while still keeping the glass effect"
13. "dimming blue for links in chat view is not good when hovering, is that what default style in browsers when you
    hover on a link? or does it show underline or something? idk that blue link and hover effect doesn't feel like
    regular link styles? idk check properly and fix it"
15. "there are weird artifacts when scrolling tables in chat view, like on table header there is some rounded corner
    kinda thing? i also see table contetn is getting clipped vertically?" (`r9-2.33.00.png`, `r9-2.33.03.png`,
    `r9-2.33.42.png`)
16. "let's increase propmt input max height to 10 lines"
22. "check this, i see chat transcript and input moves at different time when a side pane gets opened up also with
    chat view the chat is very lagging with the side pane opening etc, it might be because of current system load, but
    we should fix that input and chat moving at different times, both should adjust at once, so it doesn't feel like
    too much motion" (`.build/fb57/r9-split-5.08.57.mov`, 12.5 s at 240 fps: a chat card while a pane opens beside it)

### Track C findings

- **Cause, the flicker on a Chat ↔ TUI switch (11).** A switch to the TUI ended the chat's follow (its last viewer
  went) and so made the chat not current; the switch back showed a blank, then the loader, until the transcript was
  read again. **Fix:** the TUI of a chat that has shown follows its agent too (`follows(_:)`, on the card's and the
  floating window's terminal), so the chat stays current and the rows show at once. A chat never shown follows
  nothing, as before.
- **Fades (11).** The rows fade in over 0.2 s when they first show in a card (a card just made, a switch back, a
  history read to its end); the agent's copy of a sent message comes in at the sent bubble's 70 % and goes full over
  0.2 s, but not for rows that come with a history or Show Earlier. Both are off with Reduce Motion, as the app's
  other fades (`Animation.fade`).
- **The empty chat (10).** The reply box sits in the middle of the card under its header rows, the glyph and greeting
  above it, through a custom alignment guide (a stack passes on only custom guides; a probe showed `.center` does
  not). A short card keeps the header in view: the stack's top goes no higher than the card's.
- **The reply box (12, 16).** Its glass is tinted with the card's own color at 45 %; it grows to 10 lines.
- **Links (13).** Browsers' default style sheet (`a:any-link { color: -webkit-link; text-decoration: underline;
  cursor: pointer }`, no hover rule; checked in Safari in the VM, light): `#0000EE` light, `#9E9EFF` dark (WebKit
  267847, as Chrome and Firefox), underlined, the pointing hand, no change under the pointer. The hover renderer and
  its AppKit tracker are gone. A browser's red while pressed (`:active`) is left out.
- **Cause, the table (15).** In the sideways scroll view the scroll view offered the grid more height than it
  measured, and the cells, which fill their row's height, took it: the rows spilled 16 pt past the box (the head row
  taller, the last row cut). The grid's rounded clip, drawn over the scrolled cells, showed as a rounded fill in a head
  cell. **Fix:** the scrolled grid keeps its own height (`fixedSize` vertical; the per-cell one C5 added is gone), and
  no clip: the head's two outer cells round their own top corner. A headless probe (an `NSHostingView` laid out off
  screen, the grid's cells' frames printed) showed the spill and its fix; no UI test sees it, as a reply is one
  accessibility element.
- **Cause, the box and the rows at different times (22).** A narrow card waited 150 ms for its width to settle before
  it wrapped the rows, while the reply box followed at once; a split gives the card its final size once, so the wait
  only delayed the rows (the user's recording: the rows clipped at the old width for 18 frames at 30 fps while the box
  was narrow). **Fix:** a lone new width wraps the rows at once, with the box; one within 150 ms of the last (a drag, a
  window resize) waits for the run's end as before. The lag: the rows' one wrap at the new width (up to the newest
  block, 34 rows) is the chat's whole work in a split: the moving card lays its content out once, at its final size.
- **Runs.** Red on the old code in the VM: the box 59 pt below the middle, the loader on the switch back
  (`[loader, rows]`), the box stopping at 5 lines, the messages at the old width after the split (`["354 716", "354
  354"]`). Green on the new code in the VM: those four tests and the wide-table test; the picture run's three quick
  switches each showed the rows in every snapshot. The VM's frame strips: before, the rows clipped at the old width for
  about 0.3 s after the box went narrow; after, both in the same frame. The stand-in's `grid` scene is the repro for 15.
  Pictures: `~/Downloads/ovvi-research/p58c/`.
- **For the user.** Switch Chat → TUI → Chat on a long chat; send while the agent works and watch the bubble go full;
  hover a link; scroll a wide table sideways; open a pane beside a chat; a new chat's box in the middle.

## Track X: Codex chats from the transcript (item 14)

14. "that codex limitation for resumed chats is weird? why is that? are we relying on codex app server? or relying on
    transcript? should we change to rely on transcripy for codex as well so it works fine on resume and stuff"

    The limitation, from phase 57 Track C5: "A resumed Codex chat stays empty until its first prompt, because Codex
    starts its session only then."

### Findings (Track X)

- **How it works.** No app server: the Codex chat already reads the transcript. Ovvi launches `codex` with an inline
  SessionStart hook (and its trust hash) that appends the hook's JSON to `~/.cache/ovvi/chat/T/hooks.jsonl`; the chat
  follows the `transcript_path` there, the rollout `~/.codex/sessions/Y/M/D/rollout-<time>-<id>.jsonl`, and reads its
  `item_completed` events.
- **Cause.** Codex queues SessionStart until the first turn (`run_pending_session_start_hooks` in `session/turn.rs`),
  for a resume too. So a resumed chat's side file named no rollout before the first prompt, and the chat was empty.
- **Fix.** Before a resume line, one run on the pane's machine finds the session's rollout by its id and appends
  `{"transcript_path": …}` to the side file. A resumed Codex appends to that same file (`open_rollout_for_append`), so
  the hook's later line names it again and changes nothing. A `.zst` rollout is named by its plain path, which Codex
  makes as it resumes. Resume from Archived Sessions and Relaunch with Chat both go through it.
- **Decisions.** The rollout is looked for under `$HOME/.codex`, as Archived Sessions already reads Codex's store (UI
  tests: `-archivedHome`). A `CODEX_HOME` set only in the pane's shell is not seen: that chat fills at its first prompt,
  as before. The stand-in now honors `CODEX_HOME` (default: its own temporary folder), keeps its rollout when started
  without Ovvi's flags, reports its session to herdr then, and goes on with `resume <id>`.
- **Runs.** HerdrKit's new test and `make lint build test` green on the rebased tree. The VM stayed busy (other
  tracks), so `testRelaunchWithChatShowsACodexSessionsHistory` (with the Codex chat tests) goes to the final CI round;
  without the fix its side file names no rollout and the chat is empty.
- **For the user.** With a real Codex: resume a session from Archived Sessions and one with Relaunch with Chat. The
  history shows before the first message and does not load again at it. Once with an old, compressed (`.zst`) session.

## Track E: File Explorer and Git (items 17, 18, 19, 20)

17. "sometimes i see file explorer listing goes blank like this randomly and then comes back on its own? folder is
    still there, but something happening in the way it lists i see this. also this happens only on remote machines, i
    never saw this hapepning on mac" (`r9-2.07.24.png`)
18. "in file explorer if i have sidebar opened, and i am on certain file editor, how can i take my keyboard focus back
    to file tree? like with mouse click i can make it active but with keyboard i can't shift focus between file tree
    and editor? can we use some hotkey to toggle around between them?"
19. "in markdown for the outline thing as well, can we make it like glass button, so all three buttons on the right
    look consistent in markdown?"
20. "cmd+option+click not working in file explorer and git plugins, wherever cmd+click and option+click is enabeld,
    cmd+option+click should work too (except clicking on commit, i don't think there are any default apps you can bind
    to open diffs)"

## Findings

### Track P

- **Cause, item 7 (why it went).** Phase 48 ("instant tabs", commit 1ce19276) removed every tab motion with the strip.
  The user had asked to drop the motion between tabs; the overview's zoom and its chrome fade went with it as part of
  that cleanup, not for a reason of their own (a tile open went from 240 ms to 38 ms, all of it the 0.18 s zoom).
- **Fix, item 7.** Leaving the overview (a tile, Esc, ×, ⌃⌘O) grows the selected tab's miniature from its tile to the
  page in 0.18 s while the other tiles fade out, and the sidebar and title row fade in over 0.12 s; then the page
  shows. Smaller than the old one: no session paging, the miniature draws pictures only (a live terminal stays in its
  tile until the page takes it). At once under Reduce Motion, with the tile out of view, or on a second leave.
- **Cause, item 8.** Only ⌘D, ⇧⌘D and drops evened their run (`balance(around:)` in their write). A card opened beside
  another (`newPane(.split)`: a link, a plugin, `ovvi open`, `ovvi agent`) kept herdr's half, and a close never evened.
- **Fix, item 8.** Settings ▸ General ▸ Balance splits automatically (on by default; also View ▸ Pane and the palette).
  Every open and close in the app evens its run in the same write, best effort; a close shows the evened run ahead of
  herdr (`Ahead.layout`, the split's hold), so cards move once. Another client's open or close, a shell's exit and a
  move out of a tab even once a snapshot shows them, if the tab did not change since (cards move twice there: herdr's
  change shows first). Off: herdr's halves everywhere, as in its own window; ⌥⌘= still works.
- **Decisions.** The setting also evens panes that other clients (herdr's window, `herdr pane split`, another Mac) open
  or close in a session Ovvi shows, since the user asked for it "all the time"; that includes another client's split
  made with an explicit ratio. A pane that moves into a tab (its terminal already known) is not evened, so a tab the app
  rebuilds pane by pane keeps its ratios. A replaced pane leaves its place to the
  new one, unevened. `SplitNode.closing` evens only the run the pane was in: a row that drops to one pane stays one
  unit of its column.
- **Runs.** VM, first build: the zoom test passed; the balance test's Off half failed on the test (it reopened a folder
  `ovvi open` reuses), and the strip showed a never-shown tab land on two blank frames (its live terminal moved into
  the zoom). Final head: the tile test, the balance test and `testSplitsMoveEachCardOnceToItsPlace` (with an in-app
  close of one of three) green in the VM; the strip shows the zoom grow a picture and land with no blank frame. Strips:
  `~/Downloads/ovvi-research/p58p/`.
- **For the user.** Open the overview and click a tile, press Esc, ⌃⌘O: the tile should grow into the page while the
  sidebar and tabs fade in. Split three panes and close the middle one with ×; open a file to the side with ⌥-click;
  type `exit` in one of three panes: each time the row should end equal. Turn the setting off and split twice: halves.

## Track L: Ovvi's own load (item 23)

23. "can you also invoke one more agent to do deep analysis on how much ovvi contributes to system load, in terms of
    all commands that get run from plugins, our idle processes etc, i just want to make sure our ovvi app is not a
    heavy one adding too much load". The report: `~/Downloads/ovvi-research/ovvi-load/report.md` (Ovvi ≈ 10 % of one
    core, ≈ 300 process starts a minute, 75 % of them the sidebar's git poll; every herdr call a `remote-api-bridge`
    process). On its fixes: "1. let's do sidebar git branch fix", "3. yep let's do it", "4. yep, make sure there is no
    behavioral difference", "for the memory we already cap them right, so that's fine if it takes more memory, as long
    as system has memory we can leverage it". On the helper: "why can't we ssh and talk to its socket api as well? i
    am not understanding what value this helper adds at all", then "yep sounds good, but make sure we do this reliably
    and doesn't introduce weird edge case bugs", and to start: "okay start everything, try to have one simple approach
    for both mac and remote machines, separting them will lead to edge cases and shit, implement all of this carefully
    and reliably".

    Decided: (1) the sidebar's git branch follows git's own files (HEAD, refs) with a ≥ 60 s safety poll; (2) every
    herdr request goes to herdr's API socket, with no `remote-api-bridge`: on This Mac the socket itself, on a remote
    machine a local socket forwarded to the remote one over the host's ControlMaster (`ssh -O forward`), so one client
    code path connects to a socket path either way (D4 and D15 updated; a host that refuses stream-local forwarding
    shows a clear error, no fallback); (3) Git and File Explorer cards ignore events under `.git/objects` and ignored
    paths, wait 2 s to refresh, and use one `git status --porcelain=v2 --branch` for changes and head, branches and log
    only when refs change; (4) the Claude chat's `tr`/`sleep 0.3` loop becomes a file watch and Codex's 0.5 s
    `pane.read` check gets cheaper, with no change in what shows or when; (5) card state files are written without
    `sh`/`mkdir`/`cat`/`mv` and programs start without the `/usr/bin/env` step (the program found on PATH at each run);
    the presence marks stay as they are (cheap once (2) lands). Memory: no change.
