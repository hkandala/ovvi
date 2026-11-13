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

### Track A: Findings

- **Cause, item 1.** This Mac's login shell (it gives the environment and herdr's path) has 3 s at launch. On a busy
  Mac it ran out, and that nil counted as "herdr missing" for 30 s: the welcome put in its herdr step, whose 1 s poll
  then found herdr ("herdr is installed"). The same nil showed a window's "herdr is not installed" at launch.
- **Fix, item 1.** A shell that runs out is no answer: the next need for herdr asks again at once with 25 s, and every
  caller waits for that one run. The welcome opens only once it is answered, so its pages never change.
- **Cause, item 21.** SwiftUI's `WindowPlacement` position is not relative to a screen: SwiftUI sets the window's
  origin to (x, main screen's height − y − height), read from macOS 27's SwiftUI under lldb. The app gave it a
  position relative to the frame's own screen, so a float over a window on another monitor opened on the primary
  screen. Now x is AppKit's and y is flipped by `NSScreen.main`'s height; new windows (item 4) use the same.
- **Decisions.** Item 2: `rectangle.stack`, the app's session symbol, on both the stopped page and the Starting loader
  (alternatives: `play.circle`, `bolt.circle`, `terminal`). Item 4: a new window takes the frame a window was last
  moved, resized or closed with (macOS cascades it), else it fills the screen; nothing is saved across launches. Not
  the front window's frame: SwiftUI's placement sees the window it places among the others, at AppKit's saved frame.
  Item 5: JetBrains Mono, SF Mono and the Mac's families in one alphabetical list. Item 6: both install confirmations
  (the sheet and a card's) start with Show in New Pane off. `herdr-session.sh` waits up to 60 s.
- **Runs.** VM, first build: a window test that resized left AppKit's saved main window frame behind, and the front
  window rule opened later tests' windows at it (512 pt, tabs hidden); `forget-windows` now deletes those frames too.
  Final head: the ten touched UI tests green in the VM (welcome ×3, new window, terminal font, both plugin installs,
  stopped session, float, settings scenes). Pictures: `~/Downloads/ovvi-research/p58a/`.
- **For the user.** With two monitors of different heights, put Ovvi on the external one and float a pane (also from
  an agent's `ovvi` float) and press ⌘N: both should open on that monitor. Resize a window, press ⌘N: the new one
  takes its size and place.

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

### Track E

- **Cause (17).** A remote card has no file system events: the app checks each watched path every 2 s, under the
  10 s bound of each run over the relay. The check read its own failure (a dropped or stalled link, the bound) as a
  change, so every watcher refreshed at the very moment the machine could not answer. The tree's root listing then
  failed, and any failed root listing cleared the tree to "Can't list". The next check that answered was a change
  again, and the rows came back. This Mac uses FSEvents and runs nothing over a link, so it never showed there.
- **Fix (17).** A failed check reports nothing; the first check that answers after it reports one change (for what a
  caller's own calls missed meanwhile). A gone path prints nothing, so it is still an answer. The tree empties a
  listed root only for `notFound`; any other failure keeps its rows, its Git letters and its bar. `files.list` of a
  missing folder is `notFound` under dash too (dash says only "can't cd"). The same fix stops a remote Preview card
  showing its error on a check that failed.
- **Decisions.** ⇧⌘E, **Switch Between Tree and File** (View menu, ⌘K): VS Code's Show Explorer key, which also goes
  back to the editor; free in Ovvi's map, while VS Code's ⌘0 and ⌘1 and Xcode's ⌘J are taken or open a chooser. It
  shows a hidden tree first, gives the file's row the keys (with the focus ring), and takes them only if the user did
  not move on meanwhile. The outline toggle is a toggle with `"style": "segment"`, drawn as one pill segment. ⌘⌥ is
  `ovvi.open`'s new `how: "mac"`, routed through the terminal's `Links.open`; commits, a commit's parents, Git's home
  (the explorer bar's **Git**) and a deleted change keep ⌘⌥ as ⌘. Path crumbs take no modifiers at all (header
  clicks carry none), so they are left as they are. The API stays 3: an older app opens `mac` as a new tab.
- **Runs.** The two new HerdrKit tests fail on the old poll and listing script (no change during an outage; dash's
  `notFound`) and pass now. VM: the touched Markdown, header, File Explorer and Git tests green; the new
  `testExplorerSwitchesTheKeyboardAndOpensInTheMacsApps` first failed in its repo setup (the VM's first git after boot
  took over 10 s: that wait is now a 60 s failure bound), then on its Git step (git lists an untracked folder's files,
  so the test ⌘⌥-clicks a modified file, which opens in TextEdit), then passed. Pictures:
  `~/Downloads/ovvi-research/p58e/`.
- **For the user.** On a remote machine, a dropped link no longer blanks the tree. ⇧⌘E in a file with the tree beside
  it, and back; with the tree hidden. Markdown's three pill segments at the right. ⌘⌥-click a tree row, a Markdown
  link, a Git change and a diff's Open File.

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

### Track M

- **Cause (9).** Phase 57 L3 (c6960e8e) kept left drags from the program, so pi never selected and never copied. pi
  copies on This Mac with its own clipboard helper; OSC 52 only over SSH or with `PI_CLIPBOARD_OSC52=1`. herdr knows a
  program's mouse mode and sends it to `terminal session control` clients (`MouseCapture`), but its CLI bridge drops
  it, and it sends an OSC 52 write only to its own TUI client: neither reaches Ovvi. The upstream patch for the mode
  is in `~/Downloads/ovvi-research/p58m/herdr-mouse-mode.patch` (kept for later, unused).
- **Cause, the white block.** pi selects from the press's cell to the pointer's, both taken (`getSelectionBounds`), in
  reverse video, which herdr writes as `38;2;0;0;0;48;2;255;255;255`. Ghostty's `dragSelection` takes the press's cell
  going forward only when pressed before its 60 % point (`round(0.6 × width)` px), going back only past it, and the
  pointer's cell the other way round. Where pi took a cell and libghostty did not, the cell was pure white.
- **Fix.** A plain left drag goes to the program again and selects in the card, and libghostty gets points half a
  pixel in from the cells' edges, so it takes both end cells. A press on the wrong side of the 60 % point for the
  drag's way is made again at the cell's other edge. Before that press, libghostty gets a click at the card's far
  corner: a press within one cell width of the last one, inside the double-click interval, counts as a double click
  (a word). The restart sends nothing to herdr.
- **Decisions.** A ⇧, ⌥ or ⌃ drag and a double or triple click stay in the card, as in L3: pi treats them as plain
  drags (`button & 3`) or finds other words (`Intl.Segmenter`) and lines (from column 0), so its cells differ from the
  card's. The program gets such a single click on its release when the pointer stayed in its cell. Option A's Ovvi
  side (Ghostty's rule once herdr reports the mode) is not built.
- **Limits.** pi keeps its selection on its text when the text scrolls (its own scroll at the box's edge, new output,
  the wheel); the card's stays on the screen's rows, so white cells can show then. libghostty-spm has no call to set
  or clear a selection. A press within 1 px of the last move keeps libghostty's older point: rarely one cell off.
- **Tests.** A stand-in (`Fixtures/mouse-select`) turns on SGR mouse mode with drags, selects pi's way in reverse
  video and draws a white mark that moves with each release. The UI test (dark) drags forward and then forward-and-back
  with each end on the side libghostty's own rule leaves out, then checks: the drags reached the program, no pure white
  pixel in the row, both end cells blue, the cells past them not (a word selection reaches them). The cell geometry
  comes from the mark's pixels. For Track K: `mouseDown` now lives in `Terminal/Selection.swift`.
- **Runs.** VM: green on the fix (both tests); red with the old cell rule (no edge points: "a white cell beside the
  selection", the white `c` and `a` at the ends in the picture); red without the far-corner click (the word selection:
  "cell 2 selected, cell 1 not"). The right-click test ran only in the VM: it belongs in the final CI round.
- **For the user.** In pi, drag over text: only the blue selection, no white cell, and pi says "Copied!" with its
  formatted text on the clipboard. Drag forward and then back past where you pressed: still no white cell. A ⇧-drag or
  a double click selects in the card only. After a selection, scroll pi or let it write: pi's selection moves with its
  text and white cells can show (known limit). Pictures (dark): `~/Downloads/ovvi-research/p58m/`.

### Track L

- **Cause.** Ovvi started a process for nearly everything it asked: every herdr request was a `remote-api-bridge`
  (two execs with `/usr/bin/env`), the sidebar ran `git status` per space every 10 s (9–14 processes each with this
  Mac's wrapped git), a card's state save was `sh`+`mkdir`+`cat`+`mv`, a shown Claude chat ran `tr`+`sleep` every
  0.3 s, and Git and File Explorer cards refreshed (4 git runs, about 40 processes here) on any change under the root,
  ignored build output and `.git/objects` included, up to once a second.
- **Fix, one way for both machines.** Every herdr request and the events stream go to herdr's API socket in the app
  (`Exec.api`): This Mac connects to herdr's `socket_path` (from `session list --json`; a failed connect finds it again and retries once, on both machines);
  a remote machine to a local socket its ControlMaster forwards there (`ssh -O forward -L`, once per session and
  master; a stale file removed, an old forward cancelled first, `StreamLocalBindMask=0177`, the app's pid in the
  name, files removed at quit). A host whose sshd refuses stream-local forwarding shows "‹target› refuses to forward
  herdr's socket: Ovvi needs sshd's AllowStreamLocalForwarding", no fallback. The sidebar's branch follows git's own
  files (`HEAD`, refs, `packed-refs`, `reftable/`, `config`; a worktree's own `HEAD`): one long-lived Perl `lstat` loop
  on both machines (simplicity review, ec49d8cd), plus a 60 s read. Claude's state watch is one long-lived Perl run on both
  machines. Folder watches drop changes under an ignored folder and in `.git/objects` (one `check-ignore` per new
  output folder, then cached) and come at most every 2 s; the Git home and the Explorer take changes and head from
  one `git status --porcelain=v2 --branch` (`git.changes`), and the Git home reads branches and history only on
  `git.watch` (the sidebar's watch), a moved head, a write or Show More. Programs start by their path, found on PATH
  at each run; state files are written and removed in the app.
- **Decisions.** The remote state write stays one `sh` over the relay: a relay file op would be a second protocol for
  no Mac gain, and the read already splits the same way. The remote git watch is Perl, not the 2 s `cksum` poll the
  Explorer uses (4–5 processes a check, more than the old 10 s git); Debian's `perl-base` has no Time::HiRes, so it
  sweeps every ref file (30 ms at 10,000 loose refs; ponytail note). Terminal streams stay `terminal session` runs
  (D7). The UI fixtures that changed herdr's answers (late, down) now serve the app a socket whose connections run
  their bridge (`OvviUITests/Fixtures/bridge-socket`), so they test the same thing. An expanded ignored folder in the
  Explorer no longer refreshes while a build writes into it (documented). Codex's 0.5 s screen check is kept: it is
  now one socket request, no process.
- **Measured** in the VM, the same UI-driven scenario on 0b9f1448 (before) and this track (after), 90 s each: the
  app's direct forks (kqueue), every new pid in the VM, the app's CPU. Idle, five git spaces and a Git and a File
  Explorer card shown: forks 112 → 5 a minute (the 60 s reads), new pids 124 → 16, CPU 1.2 → 0.9 %. A build writing
  ignored output twice a second beside them (its own `date` and `sleep` are about 240 pids a minute): forks 269 → 5,
  new pids 990 → 225, the app 3.4 → 0.8 % and WebKit 1.9 → 0 %. A Claude chat shown: forks 91 → 9, new pids 292 →
  18. On this Mac's wrapped git each old git run was 9–14 processes more, so the gain here is larger than the VM's.
- **Runs.** HerdrKit: a user-level sshd on a free port drives the forward (works, 0600/0700, herdr restart, master
  SIGKILL then a stale file, the file deleted under a live master, which failed before the review's fix, refusal);
  a test herdr wrapper counts `session list` runs (one, again after stop, delete, restart); socket close on answer,
  timeout, drop, cancelled updates. VM green: the window, failure (stopped, failed stream with `down`, late snapshot,
  starts), find bar's late read, sidebar git, Git card and home, Git diff, three File Explorer, plugin API and three
  Claude chat tests. Not run here (CI's sshd): RemoteTests, ReconnectTests, RemoteBrowserTests and
  testAChatOnARemoteMachine, for the final CI round.
- **For the user.** A remote machine: connect, then drop the link (sleep the Mac or turn Wi-Fi off and on): the page
  shows Reconnecting and comes back, cards answer, the sidebar's branch still follows a commit there within about
  2 s. Restart herdr (`herdr session stop`, Start in the page): the page comes back. On This Mac a commit or a
  checkout in a terminal shows in the sidebar within about a second; a build writing into `build/` or `node_modules`
  no longer makes a Git or File Explorer card refresh.

## Round 2 (items 24–34)

Recordings in `.build/fb57/`: `r10-select-9.32.48.mov` (7.4 s: a drag-select in pi, the white block flickering),
`r10-chat-drag-9.48.49.mov` (9.8 s: a chat card while a divider is dragged).

### Track M2: the white block, simply or not at all (item 24)

24. "in pi when drag and select the white block still flickers a bit, see if you can fix it without much workarounds,
    also identify what actually introduced this issue, if its too complicated let's drop entire fix, and leave it,
    let's apply fix if its simple one" (`r10-select-9.32.48.mov`)

### Track H: every hotkey in one place, rebindable (item 25)

25. "we have so many hotkeys and shortcuts right, including in plugins and stuff, i know we have cmd+/ one to see
    shortcuts, but it doesn't cover all, we can keep only important ones in it, i am thinking we can add another section
    in settings, call it hotkeys or something and list everything, grouped accordingly, group per plugin etc, even
    custom plugin ones should be listed there, so in this settings page we should be able to cahnge hotkey as well, like
    cliking on the hotkey should record the hotkey and update it, use proper modern design and good ux there, and also
    have a search for it, so we can ssearch and update hotkeys quickly, see if we need to map all hotkeys at one place or
    something so we can see and control everything from hotkeys, hunt through entire codebase and find if we have
    hardcoded hotkeys anywhere and keep it at one central place or some way to register the hotkeys and be able update
    them from settings"

### Track T: tabs: scroll to a new tab, back and forward through tab history (items 27, 33)

27. "in tab bar, when a new tab is opened and that tab is not in view in tab scroll can we move it to that position
    automatically with scroll animaiton, essentially, if i do cmd+click and a new tab has come up and that's not in view
    then the tab bar scrolls bringing that tab in view"
33. "can we also have a shortcut to go to previously active tab, liek history forward and backward within a session, it
    can go across workspaces as well, like i think vs code or something has something similar, if the tab is closed we
    skip it, no need to reopne or anything, we skip and go to previous one to it. basically i want a quick shortcut to
    navigate across tabs based on what was last active and history, keep the shortcut simple as well, so its easy to
    remember and use."

### Track E5: explorer and Git sidebars (items 26, 28)

26. "in file explorer, for file tree sidebar when opening and collapsing can we do slide in animation like other
    sidebars we have"
28. "in git diff view as well we have a sidebar icon which expands and collapse file list sidebar but that icon is on
    right hand side, let's move that to left side, befdore home icon and also change the icon based on its state similar
    to what we did in file explorer"

### Track C9: chat glass, divider drags, endless history (items 29, 30, 31)

29. "actually in chat view revert the tinted glass, i like the previous version better" (item 12's tint)
30. "now in the chat when id do cmd+d they move together, but if i drag using resize handler there is still weird
    behavior where chat is stuck but input is moving, keep input also stuck and reset like how transcript does?"
    (`r10-chat-drag-9.48.49.mov`)
31. "in chat view, can we do auto scroll, instead of shwoing show earlier, as soon as user reaches to the end show the
    loader animation and load and keep loading automatically as user scrolls"

### Track X2: Relaunch with Chat on a resumed Codex (item 32)

32. "so for codex, i can see chat loads for resumed session, but the thing is let's say i resumed a session in codex
    using codex resume, i dont see relaunch with chat button until i type some prompt, after one prompt, i see that
    button, and relaunch with chat works fine now, and relaunched chat has transcript and works as expected, we need to
    make sure to show relaunch with chat even on resumeed codex conversation with no prompt yet"

### Track B: recently closed browser pages (item 34)

34. "for browser, can we show history icon left to the developer tools icon, and clicking on it we should show a drop
    down showing recently closed tabs, and clicking on any one should open that in new tab, and along with option+click,
    cmd+option+click support. but one thing is we should figure out how to persist that state, mostly per machine, in
    some state file or something, but we have to limit the max number of pages, may be like 20 pages or something and
    drop the old ones, it should be simple, and fetch from state file, so for any machine it comes from that state file
    or something."
