# Phase 59: Releases: a curl install, Sparkle updates, dev builds

Goal: people install Ovvi with one line, the app updates itself, and the user can run a dev build beside the public
release. No Apple Developer account yet: builds stay signed without an Apple identity, and the curl install avoids
Gatekeeper (curl adds no quarantine flag). The plan is `~/Downloads/ovvi-research/release-and-updates-plan.html`
(phases 1 to 3); its phase 3 (Developer ID, notarization) and the self-signed spike wait.

The user's words are quoted; the decisions under them are the orchestrator's.

## The user's words

1. On the plan: "okay so give me rough plan of implementing this entire release flow with no apple developer account
   and using curl based apparoch"
2. "it is public, so we are good / first version number should be 0.1.0 / in that curl script let's also ask
   confirmation to install herdr and four agent integrations on user confirmation, so herdr will be ready as well /
   for sparkle 2, let me know how to generate key and stuff, or you generate and saave it as some file in downloads
   or somewhere so i can store it in my password manager / we can skip phase 4 for now, once all done, create a html
   report for next steps, and apple developer account and phase 4 also, keep it simple, concise and clean"
3. "also one more thing can we have a dev build also, like dev build should have some indication in logo, and it can
   generate a build for any commit or the altest master, also i should be able to install both latest build and
   public release as well"
4. "let's start and build this"

## Decisions

- The repo `hkandala/ovvi` is public; releases and their files live on its GitHub Releases. The first version is
  `v0.1.0`.
- One artifact per build: a zip of the app (`ditto`), plus `SHA256SUMS`. No DMG until notarization (a browser download
  hits Gatekeeper anyway).
- Ad-hoc signed, Hardened Runtime off (Sparkle does not load under it without a Team ID).
- The installer is `install.sh`, a file on each release: `curl -fsSL
  https://github.com/hkandala/ovvi/releases/latest/download/install.sh | sh`. It asks before it installs herdr and the
  agent integrations.
- Sparkle 2 with an EdDSA key; the feed is a file on the release. The private key goes to a GitHub secret and to a
  file in `~/Downloads` for the user's password manager.
- Dev builds: a second app beside the release, with its own name, bundle id and a marked icon, built from any commit
  or the newest main, installed by the same script.
- Real public releases (`v0.1.0` itself) are tagged only after phase 58's final CI is green and the user agrees;
  testing uses pre-release tags.

## Tracks

Records the work as it lands: Findings, Runs, commits.

### Phase 59 (one agent, parts A to F)

- **Decisions.** The dev app is **Ovvi Tip** (`dev.ovvi.app.tip`, `ovvi-tip://`, `~/.config/ovvi-tip`, a DEV badge
  drawn at build time by `scripts/tip-icon.swift`): "Ovvi Dev" is the Debug build's, and a new name changes none of
  its scripts. It keeps its own copy of what the Debug build keeps (`#elseif TIP` beside `#if DEBUG` in
  `Registry.swift`; everything keyed by bundle id) and shares what belongs to sessions (herdr's jobs, `~/.cache/ovvi`,
  `~/.local/state/ovvi`). Tips build on a dispatch only: about 6 runner-minutes each on 5 shared macOS runners, with
  about 70 pushes a day. D106 and D107 were taken: the decisions are D112 (Sparkle) and D113 (releases, Tip).
- **Cause (Hardened Runtime).** An ad-hoc app under Hardened Runtime cannot load Sparkle's framework: the runtime is
  off in both configurations until a Developer ID exists.
- **Cause (a command-line build setting).** `WRAPPER_NAME` or `SWIFT_ACTIVE_COMPILATION_CONDITIONS` on xcodebuild's
  command line reaches every package target too (duplicate outputs; no `SWIFT_PACKAGE`): the app target reads
  `OVVI_APP_NAME` and `OVVI_CONDITIONS`, which only it uses.
- **Cause (the release artifact).** upload-artifact skips hidden files, and a glob under `.build` made `.build` the
  search root, so nothing uploaded: `include-hidden-files: true`.
- **Fix (the key).** The EdDSA key is an openssl Ed25519 key in Sparkle's base64-seed form. It lives only in the
  publish jobs (Ubuntu, the `release` environment, write token), which run no build tools: a Tip builds any ref's
  code in a job with no secret and a read token. `scripts/appcast.sh` signs with OpenSSL 3; Ed25519 is deterministic,
  so its signature is sign_update's byte for byte (checked, and `sign_update --verify` accepts it). Sparkle's
  Markdown shows HTML as text: the feed's notes fold no `<details>`.
- **Fix (install.sh).** One `main()`, so a cut-off download runs nothing and no child reads the script from stdin.
  A running copy is quit by the user: an Apple event `quit` from a script needs the user's Automation consent first.
- **Runs.** The VM, terminal only: the release zip through `file://` with no terminal (opens, no Gatekeeper dialog),
  then under `expect` with a fake HOME (waits for the quit, replaces the copy, installs herdr, three integrations
  current, Pi declined); with no terminal and the app running it stops with its message. Then from the real
  pre-release `v0.1.0-rc.1` and the `tip` release, both through `curl … | sh`: Ovvi and Ovvi Tip side by side, no
  Gatekeeper dialog. The update: a second Tip published, Ovvi Tip's last check set back a day, a throwaway XCUITest
  in the VM saw the notice "Ovvi 0.1.0-rc.1-tip.0c46c9d is available", pressed Update…, Install Update and Install
  and Relaunch; the relaunched app had build 3402 and the same card, and the pane's loop counted on through it.
- **For the user.** The menu bar and Activity Monitor say "Ovvi" for Ovvi Tip (as for Ovvi Dev); the badge says DEV.
  Build Tips from main: a branch's commit count can pass later main Tips', and Sparkle then offers none of them. The
  curl install links no `ovvi` skill (only `make install` does). A pre-release cannot test the release app's feed:
  `releases/latest` finds nothing before `v0.1.0`.

## Round 2: dev builds from the repo (items 68–70 of phase 58)

The user's words are phase 58's items 68, 69 and 70, and their picks: "dev builds let's go with A", "Ovvi Dev sounds
good, but i don't like the logo, can you give some 5 options to choose from", "yes for releasing md as well".

Option A: `install.sh` installs only releases (the latest or `--version X`). `make install` builds Ovvi Dev from the
checkout: its own name, bundle id, scheme and folders, a badge, no update feed, so it runs beside a released Ovvi.
`tip.yml`, the `tip` release, `install.sh --dev` and Ovvi Tip go. `RELEASING.md` at the root replaces
`playbook/release.md`.

The icon: after two sets of options (an orange badge, then channel colours), the user picked "let's go with blueprint
one": Xcode beta's blueprint style (a blue tile, a faint grid, white outlined cards).

The user, later: "our install script should also install ovvi skill if not present, and updates should be able to
update those skills too, we can ask confirmation in install script related to skills, should support claude code, pi,
opencode and codex, i think .agents is supported by most expcet claude i guess which is .claude, we can isntall at one
place in .agents and keep a symlink in .claude, and we should have a way to update during updates as well"

### Track D2 (one agent)

- **Decisions (icon).** The user picked the blueprint ("let's go with blueprint one"; Xcode beta's style: a blue
  tile, a faint grid, the cards in white outline) from a second set of five, after "why this orange? can we try
  something else? check how other apps do their dev or nightly build icons" on the first (sheets in
  `~/Downloads/ovvi-research/p59d2/`). It is a second asset set, `AppIconDev`, that `make icons` draws
  (`scripts/dev-icon.swift`, from AppIcon's 1024 px image), chosen at build time (`OVVI_APP_ICON`): no icon swap and
  re-signing after the build, as Ovvi Tip's `.icns` had.
- **Cause (icon).** A swapped `.icns` showed the old icon on This Mac for the build's own path (the icon cache keeps
  it); a fresh copy showed the new one. macOS 26 also drew Ovvi Tip's `.icns` on a light plate in the VM's Dock,
  where the asset catalog's icon has none.
- **Decisions (builds).** Ovvi Dev is `make install` alone: its name, bundle id (`dev.ovvi.app.dev`), scheme
  (`ovvi-dev`), icon and `OVVI_CONDITIONS=DEV` (Registry's folders) are `install`'s target variables, as the release's
  are `zip`'s. No feed, so no Updates settings, Check for Updates or update errors. `make app` stays
  `dev.ovvi.app.release` for the measures. Ovvi Dev shares what belongs to sessions (`~/.local/state/ovvi`,
  `~/.cache/ovvi`), as Ovvi Tip did: the cards' state follows the panes, not the app. The Debug build was "Ovvi Dev":
  it is now **Ovvi Debug** (`ovvi-debug://`, `~/.config/ovvi-debug`; the bundle id stays `dev.ovvi.app.debug`), so
  each build's name, scheme and folder match its bundle id. `appcast.sh` lost its name argument (only Tip passed
  another).
- **Decisions (skill).** The user: "our install script should also install ovvi skill if not present, and updates
  should be able to update those skills too, we can ask confirmation in install script related to skills, should
  support claude code, pi, opencode and codex". pi, Codex and OpenCode read `~/.agents/skills` (OpenCode also
  `~/.claude/skills`), Claude Code `~/.claude/skills`; all follow a linked folder (each one's skills docs). The app
  carries `skills/ovvi`; `install.sh` asks once and links `~/.agents/skills/ovvi` to the installed app's copy and
  `~/.claude/skills/ovvi` to that link. Sparkle replaces the app in place, so each update updates the skill with no
  step of its own. A skill already there stays (`make install`'s link to the checkout); a dangling link counts as none.
- **Decisions (skill, remote machines).** The app writes no skill on the machines where it puts its `ovvi` command:
  it writes nothing into an agent's own folders anywhere (its side files stay in `~/.cache/ovvi`), it would need a
  consent of its own per machine, and Ovvi and Ovvi Dev share `~/.cache/ovvi`, so the two would need a version rule
  to stop replacing each other's copy. Remote machines and other agents: `npx skills add hkandala/ovvi -g`
  (vercel-labs/skills; the README's skills.sh badge), which finds the repo's one skill with no file of its own.
- **Runs.** Both flavours built on This Mac: `make zip`'s app is `dev.ovvi.app`, `ovvi://`, the feed, AppIcon;
  Ovvi Dev (`make install`'s settings) is `dev.ovvi.app.dev`, `ovvi-dev://`, no feed, AppIconDev; both pass
  `codesign --verify`. In the VM, terminal only, against `file://` copies of the zip: `--dev` is refused, `--version`
  of a missing release stops; answering N links nothing; y links both, Claude's through `.agents`; a second build
  (0.1.1, a marker file in its skill) replaced the first in place, asked nothing about the skill, and both links read
  the new copy; no quarantine flag. Ovvi and Ovvi Dev ran side by side in the VM's Dock
  (`~/Downloads/ovvi-research/p59d2/vm-dock.png`). The UI tests that launch the Debug build by its path (the Dock's
  folder drop, two `ovvi://float` tests) passed in the VM as `Ovvi Debug.app`.
- **For the user.** `~/Applications/Ovvi.app` (the old `make install`, `dev.ovvi.app`) is left alone: the `v0.1.0`
  curl install finds it there and replaces it in place, keeping its settings (`~/.config/ovvi`, its defaults). Then
  `git pull && make install` gives `~/Applications/Ovvi Dev.app` beside it, with its own settings in
  `~/.config/ovvi-dev` (the old Debug folder, which holds only the default plugins: Ovvi Dev takes it over). The
  existing `ovvi` skill links to the checkout stay, so the curl install asks nothing about the skill.
