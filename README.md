# Ovvi

Ovvi is a native macOS app for [herdr](https://github.com/herdrdev/herdr), the terminal multiplexer for AI
coding agents. herdr keeps the spaces, tabs and panes; Ovvi shows them as live terminal cards in a
Liquid Glass window and lets you drive them with the mouse, the trackpad and the keyboard.

Website and docs: [ovvi.dev](https://ovvi.dev).

## What it does

- Sessions of This Mac and of remote machines over SSH, each session a page in the sidebar; several windows.
- Spaces with their git branch, tabs in the title row, panes laid out as herdr splits them.
- Split, zoom, resize, swap and drag panes; move them to another tab or space.
- Each space's agents in the sidebar and who needs you, with notifications and a Dock badge; Archived Sessions
  resumes closed agent sessions.
- A chat view for Claude Code, Codex, Pi and OpenCode; browser, File Explorer and Git cards; plugins.
- A Settings window (⌘,).
- The overview of every tab, and panes that float in windows of their own.
- Drop files on a pane to paste their paths (copied over first on a remote machine).
- Find in a pane, ⌘-click links, the command palette (⌘K), and keys for everything.

## Requirements

- macOS 26 or later.
- herdr 0.9.3 or later on each machine, found by `command -v herdr` in the login shell (else
  `~/.local/bin/herdr`). The Mac needs it only for its own sessions.
- Perl on remote machines (the SSH relay is a small Perl script; nearly every Unix has it).
- Dependencies: libghostty-spm (which brings DisplayLink) and swift-markdown (which brings cmark-gfm), Swift
  packages at exact pins, and the system `ssh`; nothing else ships in the app.
- To build: Xcode 27 and Homebrew (`make setup` installs SwiftFormat, SwiftLint, xcbeautify and Node from
  the `Brewfile`). The docs site needs Node 22 and pnpm 10.

## Install

```sh
curl -fsSL https://github.com/hkandala/ovvi/releases/latest/download/install.sh | sh
```

The script needs macOS 26 or later on Apple silicon. It checks the download against the release's `SHA256SUMS`,
installs Ovvi in `/Applications` (`~/Applications` when that is not writable), asks before it installs herdr and
herdr's integrations for Claude Code, Codex, Pi and OpenCode, and opens Ovvi. Add `-s -- --version 0.1.0` after `sh`
for that release, or `-s -- --dev` for Ovvi Tip, the newest dev build (of main, unless a build chose another commit),
which installs beside Ovvi. The builds are not notarized yet: a zip downloaded in a browser opens only after System
Settings ▸ Privacy & Security ▸ Open Anyway; the script needs no such step.

## Build from source

```sh
make setup      # Homebrew tools and the git hooks
make install    # a Release build copied to ~/Applications, and the ovvi skill linked for agents
make app        # the Release app only
make zip        # the release's zip of it and its SHA256SUMS (playbook/release.md)
make install TIP=1   # Ovvi Tip, the dev build, beside Ovvi
make run        # build and open the app (SESSION=<name> for one session; agents: ovvi-dev-* only)
make format     # SwiftLint's fixes and SwiftFormat
make lint build test   # checks, the build, the unit tests and the docs and license checks
make e2e        # the UI tests against throwaway herdr sessions (ONLY=… for some), on this Mac's screen
make vm-e2e ONLY=…   # the same in the Tart VM, off this Mac's screen (playbook/ci.md, The VM)
```

Pass `DERIVED_DATA=/tmp/ovvi-dd-<name>` when several checkouts build at once.

## Use it

Install herdr and open Ovvi. In its first window, pick a session of This Mac or start a new one. Open more
sessions with Open Session (⌥⌘T), add a remote machine from the machine button, and press ⌘/ for the
keyboard shortcuts ([all of them](https://ovvi.dev/docs/ui/theme-and-accessibility#keyboard-shortcuts)).

## Future work

herdr inside the app, releases with an updater, an iPhone and iPad app, image paste, floating status pills, a changes
panel: [Future work](docs/content/docs/future-work/index.mdx).

## License

Copyright © 2026 Harish Kandala. Ovvi is free software under the GNU Affero General Public License v3.0 only
(`AGPL-3.0-only`): see [LICENSE](LICENSE). The plugin API's types (`web/ovvi`) and the plugin template
(`plugins/builtin/template`) are MIT, so plugins you write can use any license. The third-party licenses are in
[`Ovvi/Acknowledgements.txt`](Ovvi/Acknowledgements.txt).

## Links

- Design docs: [`docs/content/docs/`](docs/content/docs/), published at
  [ovvi.dev](https://ovvi.dev) (`cd docs && pnpm install && pnpm dev` to run it).
- How it is built, for agents: [`playbook/`](playbook/README.md).
- Code: `Ovvi/` (the app), `Packages/HerdrKit/` (herdr calls, no UI), `OvviUITests/` (UI tests),
  `web/` (the runtime of plugin pages), `plugins/` (the built-in and extra plugins), `skills/ovvi/` (the agent
  skill), `scripts/`, `resources/` (the app icon, program icons and research notes).
