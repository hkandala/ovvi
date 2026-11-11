# Lessons

Problems that came back, and the rule that stops each. How we work is in
[workflow.md](workflow.md); this file is what to watch out for while doing it.

## Testing the UI

- **Read the failing step and its screen recording before you rerun or guess** ([ci.md](ci.md#a-test-fails-only-on-ci)).
- **Write tests for CI's machine** ([ci.md](ci.md#layout)): pick windows by identifier, select far tabs by
  key, launch motion tests with `-forceMotion YES`.
- **Make every assertion fail without the feature, and see it fail on the old code** when that is cheap
  (locally, or a throwaway tag on CI). Typical blind checks: an absence checked before the menu opened, a wait already true, a
  check a fallback also satisfies.
- **Before a click, wait for what is drawn, not for herdr's or the model's state**, or the click lands on the
  old frame (a sliding button, a moved card, a menu still loading).
- **The accessibility tree misleads.** A container's or overlay's identifier leaks onto its children (put
  ids on leaf elements, before any `.overlay`); a hidden but kept view still has its ids; a window-sized
  element takes every hit test; a plain `Text` has an empty label (read its value); lazy stacks build only
  visible rows; a container's frame is the union of its children, and `.offset` or an overflowing child moves
  a frame away from what is drawn (place with padding); `.accessibilityElement(children: .ignore)` needs
  `.isStaticText` for its value to reach XCUITest; SwiftUI's `.opacity` on an AppKit host moves its frame (fade the
  host's `alphaValue`); a `Menu` with `.menuStyle(.button)` has an empty label (find it by id); XCUITest sees no
  focus inside a web view (check that the old card lost the keys). After a change to a shared surface (ids, keys, menu order,
  the chrome), grep the UI tests for it and run the ones that use it.
- **A query can wait out the accessibility timeout (6 s).** One that reaches a web view as its page starts (a
  popup) waited 6.1 s on CI, and the app drew nothing meanwhile: wait for a new web view's element for over 6 s.
- **A redraw between a click's press and release loses the click.** A web page that redraws on every read loses
  clicks on CI only. Compare what you draw, and compare JSON from Swift with its keys sorted: a dictionary's key
  order changes per instance.
- **Scope every query.** `app.windows.firstMatch` can be a tooltip, a hover card or a floating pane, and
  menu bar items share names with context menu items. Use `app.windows[id]` and the menu's own items.
- **An accessibility client changes the app it watches**: it hides lazy-layout bugs and slows large UIs.
  Check rendering once with no client and speed on a Release build.
- **Trackpad touches can be synthesized.** An `IOHIDEvent` digitizer collection (its finger events as paths, plus
  a vendor child 0xff00/0x1777 holding the pad's `mthid` device id) on a gesture `CGEvent` (`SLEventSetIOHIDEvent`,
  field 87 the pad's registry id) reaches `NSEvent.allTouches()` as real touches, through the HID tap or a pid.
  AppKit builds touches lazily per event against app-wide state: reused finger ids after an unseen lift come as
  `.moved`.
- **Never post synthetic key events.** A key event posted with modifier flags but no modifier key-up leaves the
  session's modifiers down for every app. Keys reach the app only through XCUITest.
- **Step a posted drag by what the app did, not by a clock.** XCUITest plays a drag on a timetable from its start:
  late moves on a busy runner shorten its hold (a spring-load missed). A release posted before the app's drag session
  began, or 0.5 s after a spring-load (likely while it built the page), left a session that never ended. Release
  after `willBeginAt` or once the test saw the hold's effect (the helper's `press` and `release`).
- **Know XCUITest's input gaps on macOS.** Drags need `click(forDuration:thenDragTo:)`; scroll is a wheel
  with no phases; a ⌘ key whose menu item is disabled is never delivered. Real trackpad gestures go
  through the e2e helper as HID events. It cannot read a menu checkmark (`isSelected` is false) or a tooltip (build `.help` and
  `.accessibilityLabel` from one string and read the label), hear an announcement, type through an input method
  (`typeText` skips marked text) or drive the Dock menu: check those by hand (`AXMenuItemMarkChar`, a screenshot).
  An ad-hoc build shows no Dock badge or banners: tests read the `app.badge` value.
- **Debug builds are `Ovvi Dev.app`, `dev.ovvi.app.debug`, never the user's `Ovvi.app`, `dev.ovvi.app`.**
  Anything keyed by the bundle id (defaults, saved windows, the URL scheme, notifications, Launch Services, an
  `XCUIApplication(bundleIdentifier:)`) once reached the user's own Ovvi; keep new keys on the bundle id. The
  executable is `Ovvi` in both: never find the tests' app by its process name (`pgrep Ovvi`), find it by its
  session. An old Debug build on disk keeps its Launch Services registration (and `ovvi://`) until it is deleted
  or unregistered (`lsregister -u`). Tests still share defaults and saved windows with each other and with dev
  runs: pin settings with launch arguments, reset them in teardown, launch with `-ApplePersistenceIgnoreState`
  (which also saves no windows at ⌘Q). Saved windows live in `$TMPDIR/dev.ovvi.app.debug.savedState`: a restore
  test clears them first (`forget-windows`).
- **The argument domain drops a value it cannot read as a property list** (`-machines []`, any JSON): read such
  arguments from `ProcessInfo.arguments`. The machine list's guard read the domain, so a test launched without
  `-session` loaded the user's machines, and the new-window view tried their SSH.
- **Every app with the installed bundle id shares its saved windows and defaults.** A Release build run by hand (a
  measure) quit with its throwaway session's window, and the user's next launch restored that window instead of
  theirs. `make app` builds `dev.ovvi.app.release` (scheme `ovvi-release://`); only `make install` and `make dmg`
  build `dev.ovvi.app`. A measure still shares `~/.config/ovvi`: pass `-configFolder`.
- **Each test restores what it changes** (defaults, herdr focus, the pointer, leftover sessions) and reads
  fixture ids from herdr instead of assuming them; otherwise it passes alone and fails in its shard.
- **Convert a screenshot to sRGB before you read its pixels.** Screenshots come in the display's profile
  (Display P3, "Color LCD"):
  `sips -m "/System/Library/ColorSync/Profiles/sRGB Profile.icc" in.png --out out.png`. A screenshot's size is
  in pixels (divide by `backingScaleFactor`). Glass colors depend on the wallpaper: compare Glass looks on one
  desktop. `ImageRenderer` in a `swiftc` script measures a view's pixels without the app.
- **A capture draws glass its own way.** ScreenCaptureKit with a filter that names the windows it takes (an app's, its
  backdrop's too) draws their behind-window glass over nothing: dark 33 and light 241, where the screen shows 26 over
  black and 249 over white. Only an excluding filter (the display minus every other window) draws it as the screen
  does. So the welcome's clips film with an excluding filter cut to the window's rect, rebuilt every 0.25 s, and any
  other window over that rect deletes the film and fails the take. `screencapture -l <window>` also draws Glass over nothing:
  capture a screen region (`-R`) to see the real look. Tag the clips sRGB: AVFoundation plays sRGB values
  tagged bt709 lighter (33 as 36). A recording backdrop covers only the recorded window plus a small margin and goes
  away with the film: a full-screen one left up between takes locked the user out.
- **CI's screenshots and recordings show no web content.** Browser, plugin, Markdown and diff cards look blank there;
  their accessibility values are right. Check web cards through accessibility; check a page's pixels in the VM.
- **A test server never uses Python's `http.server`.** Its `getfqdn()` makes macOS show the Local Network prompt over
  the window. Bind `socketserver.ThreadingTCPServer(("127.0.0.1", port), Handler)`.
- **A test never starts a real agent on the Mac.** A pane's shell finds the real `claude`, which writes `~/.claude`:
  a test that types an agent's name skips that part where the agent is installed and leaves it to CI's stand-in.
- **A plugin label written by hand needs an iid of exactly 6 `[a-z0-9]` characters,** or the pane stays a terminal
  with no error ([Labels](../docs/content/docs/plugins/labels.mdx)).
- **Never assert wall-clock time.** In unit tests compare against a ten times larger input or count the
  work.
- **A pane's row that wraps at a space drops it.** herdr's `pane.read` keeps no trailing spaces, so a typed line
  read across a wrap lost its space (`claude--resume`) and missed its match on CI's narrow cards only. Wait with
  `waitFor(_:toShow:)`, which compares without whitespace.
- **Profilers launch by bundle id.** `xctrace --launch` with an app name started the user's installed Ovvi.app with
  test arguments. Launch the test build by its full path, and delete the 12-26 GB traces it leaves in
  `$TMPDIR` after each run: they filled the disk twice.

## CI and git

- **A flake is a bug** ([ci.md](ci.md#a-test-fails-only-on-ci)).
- **Check exit codes; never pipe a check through `grep`.**
- **The 400-line file limit is a shared budget.** Several tracks add to the same big files: split a file that
  is close to the limit before adding to it, and check it after each rebase.
- **A starved Mac fails HerdrKit's timed tests.** With many agents building, starting a process can take 20 s or
  more, and the integration tests' time limits run out (no race: longer limits only move the break). When
  `uptime` shows a load in the hundreds, run `make test` again once before you chase a HerdrKit timeout.
- **Automated rewrites change meaning.** Formatter rules and scripted replaces have flipped logic or matched
  nothing. Read the diff; make every scripted edit fail loudly when it matches nothing.
- **No pattern kills on the user's Mac.** macOS `pkill -f "x" -P 1` read `-P` and `1` as more patterns and sent
  SIGTERM to every process whose command line held a "1": the user's apps, other agents, two builds.
  Kill the exact pids you started; a pattern only when anchored to a full path of your own, checked with `ps` first.
  `make lint` rejects `pkill` and `killall`.

## herdr

- **Spike each herdr call in the exact shape the code sends, and check its side effects** on focus, folders
  and defaults: `pane.swap` moves focus despite `focus:false`; `pane.move` without a target splits the
  focused pane; some calls write outside the throwaway session (`worktree.create` writes to
  `~/.herdr/worktrees/`, so tests never call it). Trust the spike over the design pages.
- **Control keys go through `pane.send_keys`, never in `pane.send_input`'s text.** herdr pastes text into a
  program that turned bracketed paste on (zsh, bash 5.1+, fish at their prompt), and a pasted ⌃U or ⌃C is a plain
  character. Spike a typed line against a shell at its prompt, not only one still starting.
- **`agent.prompt` needs a foreground process with the agent's name** (`claude`), also for an agent reported with
  `report-agent`: a stand-in agent runs under that name.
- **herdr ids repeat:** tab ids (`w1:t1`) across sessions, session names across machines. Key state by
  (machine, session, id).
- **Once a pane has an agent session, herdr takes no more state reports for it.** A stand-in that must look busy
  reports `working` before it reports its session.
- **Scripts that run on a machine meet dash** (`/bin/sh` on Debian and Ubuntu), where a background job's stdin is
  `/dev/null`. Test a remote shell script under dash too.
- **Validate outside input before it reaches argv or a shell:** `ovvi://` URLs, herdr metadata, dropped
  file names. Reject names that start with `-`.
- **Machine-wide resources have a budget too:** ptys (`kern.tty.ptmx_max`), herdr sessions. Make a stress
  session inside one test run and delete it in the same command.

## SwiftUI and AppKit

- **A motion has one target, known when it starts, and nothing moves a card after it lands.** Split fixes made one new
  artifact after another because four parts moved cards: SwiftUI's layout, Core Animation, herdr's later
  snapshot (applied after a 0.13 s hold, so a stale one moved every card again at landing) and the content's relayout
  at landing. Hand a layout shown ahead of herdr over only when herdr's tree puts every pane in the same place; lay a
  moving card's content out once, at its final size; and check a change with the per-frame track
  (`testSplitsMoveEachCardOnceToItsPlace`), not a single mid-motion sample.
- **Never give a `ScrollPosition` binding back what the scroll view wrote into it.** It names a row as a scroll
  begins or ends, and the next body puts that row back at the top: a jump. Use a binding that
  drops the writes and set it only for the app's own scrolls. `defaultScrollAnchor(.bottom)` alone follows new rows
  only at the exact bottom, and keeps the offset when scrolled up by any amount.
- **Inside a sideways scroll view, a SwiftUI scroll view of both axes gets no vertical wheel**: only its
  scroll bar moves it. Nest one scroll view per axis. A probe window that sends wheel events to itself
  (`window.sendEvent`) shows it without the GUI.
- **Re-check state after every `await` and before every delayed effect**: state read before an await, late
  drop or hover events after the action ended, an older write winning over a newer one, a double click
  starting two connects. Use generation counters and structured `.task`.
- **Design for the user's scale from the start:** hundreds of panes and tabs, remote machines, several
  windows. Anything built per tab costs at 300 tabs: build lists when a menu opens, no `@State` writes per
  frame, test hooks read once into a `static let`.
- **Never hide and fade to mask a flicker.** Keep the old frame shown until the new one has drawn.
- **View identity cuts both ways.** A view shared by all spaces carries stale scroll and lazy state; an
  `.id` per page makes a fresh view that flickers at offset 0.
- **WebKit scrolls on its own thread: a scroll listener runs a frame or more behind.** A clip or a cover set from one
  showed rows under a sticky header in a fast scroll. Tie what must follow a scroll to CSS (`position:
  sticky`, opaque), and check a fast scroll frame by frame.
- **SwiftUI's `.onDrop` is an AppKit view of its own** (`DraggingDestinationView`, for any data), under the view
  it is on. Opacity 0 and `allowsHitTesting(false)` do not stop it: a kept page's took every drop from the shown
  page below it. Make it only while its view shows (`.background { if shown { … } }`).
- **An overlay blocks every input path to the page below:** swipes, the wheel, menu shortcuts and clicks.
  Check all of them when you add one.
- **A new or lazy scroll view's first layout lies.** The first scroll position gets dropped,
  `containerRelativeFrame` resolves to the window, `.task` in a lazy stack is cancelled, and overlays get
  clipped. Use `defaultScrollAnchor(_:for: .initialOffset)`, a GeometryReader, or `onAppear` plus a Task.
- **A list typed into stays in AppKit.** With an accessibility client attached (Raycast, VoiceOver, XCUITest), every
  SwiftUI row made or changed walks all the window's focusable views; each live glass element (a keycap) is a SwiftUI
  host of its own, and so is a hosting view per table cell. The palette's rows took 136–173 ms a key that way and
  25–28 ms drawn in a reused `NSTableView`. Time a list with its rows hidden first: that is its floor.
- **A lazy stack's height is a guess** from the rows it built, often 2–3× off, and it changes as it measures more.
  Anchored at the bottom, a resize jumps to the end, or past it to a blank view: lay out a short plain stack instead
  (the chat, D95), and test a one-step resize too (Reduce Motion). Fed back into its own frame (`onGeometryChange` into
  the list's height), it made the palette's list 45 times in one turn for one typed key (300 ms): clamp the
  read to the most the frame shows. Give each `ForEach` element one view: a header beside its row made the stack make
  5 to 8 times as many rows. Count bodies per key before you guess.
- **An environment change alone does not call `updateNSView`.** A representable that reads a value from
  `context.environment` there misses its changes (kept pages' hosts never hid or showed again). Pass the value as a
  stored property, read in a view's body.
- **SwiftUI lifecycle traps:** it keeps the first closure (read current state inside actions); a first
  responder set during an update is undone (take focus on the next run-loop turn); a `@State` initializer
  runs again on every parent rebuild (no side effects in it); the menu bar refreshes only when the focused
  value changes.
- **Measure before you optimize.** Observation notifies on in-place edits that change nothing;
  `allowsHitTesting` and per-move `@State` re-run whole subtrees; hidden views still lay out. Tools: one log
  line, an in-app frame probe or scroll meter, `sample` on the running app, a tiny probe app, the user's
  capture read frame by frame; memory and CPU with `footprint <pid>` (it leaves purgeable IOSurfaces out) and
  `top -l 2 -s 10 -pid <pid>`; xctrace's Animation Hitches crashes on attach. Measure keys and speed on a
  Release build launched by hand (`open -n`), with Quartz events: `sample` triples a key's time and
  XCUITest's accessibility snapshots dominate at scale. A frame meter's display link asks for the display's full
  rate (ProMotion runs one at 60 Hz otherwise) and records the main thread's CPU per frame: a long gap with little CPU
  waited on the render server, not on the app. Under a busy Mac, compare before and after in turns, not hours apart.
- **A `ScrollViewReader`'s content runs again only when what its closure captures changes.** `@State` or an
  environment value read only inside it is no dependency of the body, so its change redraws nothing (a button that
  never showed). Read them into `let`s in the body and use those inside; observed models are tracked inside.
- **A busy app's `DragGesture` reports its first change late,** after the pointer moved on. Take the grab from
  `startLocation`, never the first `location`: the late one put a dragged row's image off the pointer and its drop a
  row short.
- **Take a hit frame outside any offset that moves a view for a while** (a slide, a landing). `onGeometryChange` inside an
  `.offset` saw the offset set but not always its return to 0, and the sidebar lit the row 50 pt under the pointer:
  measure in the view's own space and place it by a frame taken outside the offset.
- **A view that leaves its window gets no `resignFirstResponder`:** a hidden tab's page keeps its focus flag. Clear
  it in `viewDidMoveToWindow`.
- **On macOS 27, a SwiftUI drop target made after a drag entered the window never gets the drop.** Make every target
  before the drag starts, hidden.
- **Return never presses a `confirmationDialog`'s destructive button.** A dialog that Return confirms is an `.alert`
  with a `.defaultAction` and a `.cancel` button. `role: .destructive` draws nothing on `.glass` buttons: tint them.
- **WebKit draws an overlay scroll bar under its children's `z-index` layers** unless the scroll view is a stacking
  context (`isolation: isolate`).
- **Hover state is unreliable.** A view removed under the pointer gets no hover end, and a busy app runs
  hover late. Decide from the pointer's location when it matters.
- **WebKit cannot end its own helper processes here** (xpc: "Operation not permitted"): a GPU or page process it gave
  up on lives on, and its pages stayed blank with no delegate call. Force a hang with SIGSTOP, not only a
  `kill -9`, and check the log for "Could not signal".
- **A web page takes the keyboard by itself.** WebKit makes its web view first responder when the page focuses an
  element (`PageClientImpl::makeFirstResponder`), and `NSWindow.makeFirstResponder` never asks `acceptsFirstResponder`:
  refuse in `becomeFirstResponder`, and give the keys back, since the old responder has resigned by then.
- **Every key has three possible owners: the menu, SwiftUI and libghostty.** libghostty takes every key it
  gets and `NSMenu` swallows a disabled item's key. Log the menu action and `keyDown` in the first run
  before guessing.
- **Don't block Swift's cooperative pool** (`Process.waitUntilExit` in async code): await the exit through
  `terminationHandler`.

## The real app

- **Driving the real app by hand finds what the suite misses** (keys typing characters, a cold Dock drop).
  Write the test after the bug is found.
