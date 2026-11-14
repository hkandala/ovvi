# CI

How CI runs, how to run part of it, and how to keep it green and fast.

## Layout

- **Workflows.** `.github/workflows/ci.yml` runs the checks on every push to main and on pull requests,
  except docs-only changes (`playbook/**`, `docs/**`, `resources/**`, `**/*.md`): those start no run. The
  UI tests run only on a dispatch.
- **Releases.** `.github/workflows/release.yml` publishes a release from a version tag on main
  ([release.md](release.md)).
- **Docs site.** `.github/workflows/docs-deploy.yml` builds the docs and deploys them to the Vercel project
  `ovvi` when `docs/` changes; Vercel's own git deploys are off. Run the `vercel` CLI only from the repo
  root: in another folder `vercel pull --yes` creates and links a new project.
- **Machines.** `runs-on: xcode-27`: a VM with a 1x display (a 1024 × 674 pt screen), the US keyboard layout
  and Reduce Motion on; 3 cores and 7 GB, and one runner can be half as fast as the next. The account has 5 macOS
  runners: GitHub's limit for every plan below Enterprise, shared by all of the account's runs. herdr is downloaded
  and checked by its SHA-256 (`scripts/ci-herdr.sh`). At 1x, cell sizes round: `stty size` can be one column
  narrower than the card's grid, and a 1 pt font step can leave the column count the same, so grid tests allow one
  column. A second ⌃⌘F during the full-screen animation is lost.
- **Checks** (a push or a pull request): one job, `checks`, runs `make lint`, `make build`,
  `make build-tests` (the UI tests compile), and `make test` (HerdrKit, the acknowledgements,
  the Settings rows (`scripts/check-settings.py`) and the cli.mdx script checks). It takes about 3 minutes.
- **Full run** (a dispatch): a `build` job (`make build-tests`, its products uploaded as a tar), then five jobs
  (`test (0)` to `test (4)`), each a shard of the UI tests, which run that build (`make e2e PREBUILT=1`:
  `test-without-building`) and reach their first test about a minute after they start, half of it the e2e helper's
  tools (`swiftc`, 20–40 s). A chosen-tests run builds in its one job. Every test job starts CI's sshd on localhost
  for the remote-host tests (`scripts/ci-sshd.sh`). The image has xcbeautify and node.
- **Shards by time.** `make e2e SHARD=i/5` runs the tests that `scripts/shard.py` gives shard i: the slowest
  test first, each to the shard with the least time so far, from `scripts/test-times.tsv` (a test not
  listed counts 15 s).
- **On-demand tests.** The Makefile's `ON_DEMAND` list (stress tests, cost and memory measurements,
  frame-record tests, the look scenes) is left out of `make e2e` and of full runs. Run them before a release
  and after a change to what they measure.
- **Results.** Each test job uploads `e2e-xcresult-<shard>`: the xcresult with screen recordings, also of
  green runs.
- **Time.** A full run takes 24–30 minutes and about 100–107 runner-minutes: about 4 minutes of the build job, then
  about a minute of setup and upload per test job and a fifth of about 5300 s of UI tests, 276 of them (the slowest
  shard ends 4–9 minutes after the fastest: runners differ in speed, and one shard of times from before a change can
  run 5 minutes over the others). An on-demand run takes about 17 minutes and 53 runner-minutes: the build job, then
  four jobs of 11–14 minutes for about 2500 s of on-demand tests, 22 of them. The build job does not shorten a lone run, but it saves four builds, about 12 runner-minutes a
  run. Two full runs dispatched together take about twice as long as one, since the second waits for runners, and any other run (a chosen-tests run) takes one of the 5. A test job
  stops at 30 minutes (`timeout-minutes`): a slow runner's shard can take 20 minutes after every test passed. Each test stops at 120 s, so the limit costs a green run
  nothing. Refresh the test times when tests are added, or the shards stop balancing.

## Running part of it

| What | Command | Machines |
|---|---|---|
| Checks | push to main | 1 |
| Full run | `gh workflow run ci.yml --ref main` | 5 |
| Chosen UI tests | `gh workflow run ci.yml --ref main -f only_testing=OvviUITests/OvviUITests/testA,OvviUITests/OvviUITests/testB` | 1 |
| On-demand tests | `gh workflow run ci.yml --ref main -f on_demand=true` | 4 |
| Same locally, to explore | `make vm-e2e ONLY=…` (in the Tart VM; busy: use CI); `make e2e ONLY=…` only under the GUI lock | the VM; this Mac |

- **Find your run:** `gh run list --workflow ci.yml --limit 5 --json databaseId,headSha,event,createdAt`,
  the one on your commit (or created after your dispatch).
- **Watch it** in a background command, not a polling loop: `gh run watch <id> >/dev/null; gh run view <id>
  --json conclusion,jobs`. Trust the `conclusion`: `gh run watch --exit-status` has exited 0 on a failed
  run. A chosen-tests run takes about 2.5 minutes for two tests.
- A push cancels the checks run in flight (`cancel-in-progress`). A dispatch never cancels a run and is
  never cancelled. Only the orchestrator dispatches full runs ([workflow.md](workflow.md#ci)). Use
  chosen-tests runs for single checks.
- **Judge a run by which tests failed**, not by its color, and give each failing test to the track that owns
  it.
- **Old code or work in progress on CI** (a remote probe while the GUI is busy, or to prove a test is red
  on the old code): commit on a detached HEAD, push a tag, `gh workflow run ci.yml --ref <tag> -f
  only_testing=…`, read the result, delete the tag. The hooks still run on that commit (no `--no-verify`):
  the old code builds, so revert only the fix and keep the new test.

## A test fails only on CI

1. Check which commit the red run was on: often a later commit already fixed it.
2. Read the result before guessing: `gh run download <id> -p 'e2e-xcresult-*'` (one per shard), then
   `xcrun xcresulttool get test-results tests|activities --path …` for the failing step and its values, and
   `xcresulttool export attachments` for the screen recording (`ffmpeg -ss <s> -frames:v 1` gets a frame).
   A failed test also keeps the attachment "plugin console": every plugin page's console lines and errors since the
   test began (the plugin logs in the tests' config folders), as CI's recordings show no web content.
   A recording gets a frame only when the screen changes (about 17 fps on CI, one every 0.3–0.6 s while a
   test takes screenshots in a loop), so a one-frame jump shows only by luck: use `FrameProbe` for that.
3. Think of CI's machine ([Layout](#layout)); Option sends Alt there.
4. A shard where every test from one point on runs out its 120 s with no assertion (the session log shows a launch
   whose pid never came, then "requesting to start screen recording" with no answer) is the runner's
   `testmanagerd`, not the tests: judge the tests before that point, and the next full run.
5. Give it 20 minutes from the logs. Then simplify the test or the feature and write it down, or hand it on.
   No debug branches.
6. Never rerun to green: run again only after a code change. A flake fix is proven by two full runs in a
   row green on the first try.

## Writing fast tests

- Wait with `exists(within:)`, `vanishes(within:)`, `has(_:_:within:)`, `until` or `poll` (100 ms polls).
  XCTest's own waits take over a second even when the condition already holds; lint (`fast_waits`) rejects
  them.
- Fail an async helper with a thrown error, never `XCTFail`, and keep tearDown sync: a failure that waits
  for the main actor in teardown hangs until the 120 s allowance and loses its recording. In tearDown, move
  the pointer off the chrome and restore state before the tabs it lives in close.
- A launch costs about 2.5 s, and the quit before it about 1 s more: the app is killed at once, but XCTest checks for
  its exit once a second. Relaunch only when the launch is what the test checks. A test that launches before it uses
  the app gets no launch from setUp: `OvviUITests/OwnLaunch.swift` lists them, and `make test` checks the list
  (`scripts/check-launches.py`).
- A test may walk several flows that share their setup. Start each part with `step("…")`: the part is an activity in
  the result, and its name comes before each failure's message.
- An element query takes 0.1–0.2 s and a click about 1 s: check the outcome through one herdr call or one
  accessibility value, not a walk over many elements.
- Keep a test under about a minute: one long test sets its shard's time.
- Make a failure say what it saw (put the pane's text or both values in the message).
- To test what shows before herdr answers, freeze the session's server: the e2e helper's `POST <session>/pause`
  and `/resume` (SIGSTOP, SIGCONT). Always resume in tearDown.

## Refresh the test times

When tests are added or get slower, rewrite `scripts/test-times.tsv` from two or three green full runs (dispatches): the
mean of the passed tests, from each shard's artifact:

```sh
xcrun xcresulttool get test-results tests --path <e2e.xcresult> | jq -r '.. | objects |
  select(.nodeType == "Test Case" and .result == "Passed") | "\(.durationInSeconds)\t\(.name | rtrimstr("()"))"'
```

Round the means to whole seconds: `scripts/shard.py` reads integers.

## Tried and dropped

- `-parallel-testing-enabled`: it runs copies of the app on one Mac, and UI tests cannot share one mouse
  and one bundle id.
- A faster quit between tests: XCUITest ends the app with a kill, and its 1 s is its own exit check (a once-a-second
  wait); a kill by the e2e helper left XCUITest's app state "running", so the next launch waited longer.
- Caching Swift packages: libghostty's 190 MB xcframework restored in 2 s, but build and setup stayed
  65–105 s per job.
- More shards: the 5 macOS runners are the plan's limit, so a sixth shard waits for one of them. Nested VMs on a
  runner: GitHub's Apple Silicon runners are VMs that cannot start another.
- Build flags (`COMPILER_INDEX_STORE_ENABLE=NO`, skipped package validation, a blocked
  `developerservices2.apple.com`): no gain that showed above the runners' own spread (the same build took 105 s on one
  runner and 146 s on another).

## The VM

Exploratory UI test runs on this Mac go to one Tart VM, `ovvi-test`; tests of a defined flow go to CI
([UI tests run in the VM or on CI](workflow.md#ui-tests-run-in-the-vm-or-on-ci)).
Nothing on the host isolates XCUITest: the runner asks `testmanagerd` to post HID events into the login session,
so the pointer moves on every display, virtual ones (`CGVirtualDisplay`, BetterDisplay, DeskPad) too. A VM is
another login session, with its own pointer, keyboard and screen.

- **Set up once.** `brew install openai/tools/tart` (as on this Mac);
  `tart clone ghcr.io/cirruslabs/macos-golden-gate-base:latest golden-gate` (about 34 GB);
  `tart clone golden-gate ovvi-test`, then grow its disk ([Disk](#the-vm)); and `jq`. The script runs `ovvi-tart`
  from the Tart VM plugin in this tree (`plugins/extra/tart-vm`); the plugin itself, to watch the VM in a card,
  installs as its README says.
- **The image.** `golden-gate` (from `ghcr.io/cirruslabs/macos-golden-gate-base`): the host's macOS, the Command
  Line Tools, no Xcode, user and password `admin`, logged in at boot, Screen Sharing on, and Tart's guest agent
  (`tart exec`). It stays clean: `ovvi-test` is a clone of it (`tart clone golden-gate ovvi-test`; an APFS copy,
  instant). A dirty `ovvi-test` is deleted and cloned again; the next run sets it up again by itself (about 30 s).
- **Nothing is built or installed in the VM.** `make vm-e2e` runs `build-for-testing` on the Mac, then
  `scripts/vm-test.sh`. The script boots the VM or keeps the running one (`plugins/extra/tart-vm/bin/ovvi-tart
  start`) with two shares: the Mac's Xcode, read only (the guest's `/Applications/Xcode.app` is a link to it, and
  `xcodebuild -runFirstLaunch` runs once), and `/tmp/ovvi-vm/runs`, where each run gets an APFS copy of the build
  products, `scripts/`, the tests' fixtures and the Mac's herdr. The tests find their fixtures and scripts by the
  checkout's path (`#filePath`), so in the guest that path links to the run's copies. In the guest,
  `scripts/e2e.sh xcodebuild test-without-building` runs the `.xctestrun`, and the xcresult lands in the share, then in
  `$DERIVED_DATA/vm.xcresult`. The guest's `/usr/bin/git` finds that Xcode's git through `xcrun`, about 9 s over the
  share until `xcrun` caches it in the guest's temporary folder, which a boot empties; the script runs `git --version`
  once before the tests, or the app's first git calls (5 s each) come back empty.
- **Permissions.** None to grant: `automationmodetool` says the image needs no authentication for Automation
  Mode. Two alerts of macOS would sit over the tests and take their clicks: whether a program that captures the screen
  may go on (a `screencapture` through `tart exec` or ssh, a UserNotificationCenter alert, again after a month) and
  "App Running in Background", an alert that the open-at-login test brings. Before each run, `scripts/vm-alerts.py`
  answers both in the guest (the screen: approved; that alert's notifications: off) and the script closes an alert
  still open. The tests' app asks for no notifications (`-askNotifications NO`): macOS's ask, a banner over the
  window's top right, came at every launch while no one answered it.
- **Cost.** 4 cores and 8 GB (about 4.6 GB resident while tests run). A boot takes about 40 s to a working
  `tart exec`. On a running VM, a run of two short tests takes about 30 s (11 s of tests). The first run on a new
  clone adds about 30 s of setup. Idle, the VM takes about a quarter of a core.
- **Disk.** `ovvi-test` has 100 GB (about 56 GB free): the image's 50 GB left about 4 GB, and a low-space purge
  killed a test runner. To grow it: stop the VM, `tart set ovvi-test --disk-size 100`, boot, and in the guest
  `yes | sudo diskutil repairDisk disk1`, `sudo diskutil eraseVolume free free disk1s3` (the recovery container,
  which sits after the main one), `sudo diskutil apfs resizeContainer disk1s2 0`. Tart's disk is a sparse file: the
  Mac's disk holds only what the guest wrote (37 GB). Each run removes what it left in the guest (its processes and
  xcodebuild's folder), also after a kill, and stops under 8 GB free. Only the links at the checkout's path stay; the
  next run points them at its own copies.
- **Its screen.** 1024 × 768 points at 2x, not CI's 1x 1024 × 674. The user watches it in an Ovvi pane: New pane ▸
  Tart VM (the plugin's README installs it). The VM runs `--suspendable`: the card's **Open in Tart** suspends it and
  resumes it in Tart's window (about 8 s, refused while a run holds the lock); closing that window suspends it, and the
  next run resumes it headless. A resumed guest keeps its old lookups in the shares, and the files it saw before
  (xcodebuild) are gone for it; a run that finds the shares stale mounts them again in the guest (`mount_virtiofs`),
  with no restart.
- **Limits.** Apple allows 2 macOS VMs per host; after a few start and stop cycles the limit error can stay until
  the host reboots (Tart #1217), so the VM stays running. The guest's macOS must not be newer than the host's: a
  host update needs a new `golden-gate` (`tart clone ghcr.io/cirruslabs/macos-golden-gate-base:latest golden-gate`,
  about 34 GB). The guest's GPU reports an old Metal family: it renders, but timing is slower, as on CI. The
  guest's password is `admin`, on the host's private network only.
- **More slots.** One VM is the rule: two 8 GB guests plus the agents' builds make this Mac swap. A Mac mini on the
  network with the same setup would add two.
