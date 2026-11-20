# Scripts

Run them from the repository root. When a Makefile target runs a script, use the target.

## By hand

| Script | Use it to |
|---|---|
| `herdr-session.sh up\|down <name>` | make or delete a throwaway herdr session (`ovvi-dev-*`, `ovvi-e2e-*`) |
| `stress.py <session>` | fill a throwaway session with hundreds of tabs and panes, to check speed |
| `reset-app-data.sh [--dry-run] [bundle id]` | delete the local data of one Ovvi build, to start as on a fresh install |
| `record-onboarding.sh [clips\|encode\|films\|all] [dark\|light\|both]` | record the welcome's clips and films again after the look changes ([below](#record-the-welcome)) |
| `docs-pictures.sh [derived data]` | take the docs' ten pictures again (`docs/public/images`), at 2x, in the Tart VM, after `make build` |

## Run by make

| Target | Scripts |
|---|---|
| `make test` | `check-settings.py`, `check-launches.py` (`--write` rewrites the list), `check-plugin-versions.sh` |
| `make e2e`, `make vm-e2e` | `e2e.sh`, `e2e-helper.py`, `shard.py` with `test-times.tsv`, `vm-test.sh`, `vm-up.sh`, `vm-alerts.py` |
| `make icons` | `app-icon.py`, `dev-icon.swift` |

## Used by other scripts and tests

- `e2e-helper.py` compiles `posting.swift` with `drag.swift`, `file-drag.swift`, `swipe.swift` and `pinch.swift`,
  and runs `usage.swift`, `record-window.swift` and `stress.py` for the tests.
- `stand_in.py` and the `*-stand-in.py` agents play Claude Code, Codex, OpenCode and pi in the chat tests and the
  welcome scene.
- `welcome-scene.sh`, `welcome-scene/` and `onboarding/` build the scene that `record-onboarding.sh` films and
  `docs-pictures.sh` takes, on the 2x display of `hidpi-display.m`. `vm-test.sh` runs the VM's tests on one too
  (`mirror`, so the VM's own screen shows them).
- Ovvi Dev's Settings ▸ General ▸ Rebuild runs `rebuild.swift`: the window with make install's log.

## CI and releases

- `ci-herdr.sh`, `ci-sshd.sh`, `ci-display.m`: the herdr of CI, its sshd for the remote tests, and the test jobs'
  1024 × 768 screen at 1x.
- `install.sh`: the curl installer, published with each release.
- `release-notes.sh`, `appcast.sh`: the notes of a release and its update feed ([RELEASING.md](../RELEASING.md)).

## Record the welcome

`record-onboarding.sh` records the five clips that the welcome plays (`Ovvi/Onboarding/Clips`), in dark and light,
and then two films of the whole welcome (`testWelcomeFilm`). It takes about 30 minutes, and it uses the screen,
the pointer and the keyboard of the Mac that runs it. Record when no one uses the Mac.

Before you record:

1. Install `herdr`, `node`, `ffmpeg`, `claude` and Xcode.
2. Start the script from an agent's pane: it has `ANTHROPIC_API_KEY` or `ANTHROPIC_BASE_URL` in its environment.
   Claude Code in the scene signs in only with those variables, never with `~/.claude`.
3. Give the terminal app Screen Recording and Accessibility access (System Settings ▸ Privacy & Security). The script
   stops and names the one that is missing.
4. Quit Ovvi Debug.

Then run it on this Mac's screen while the user said they are away (playbook/workflow.md, The GUI lock):
`HEAVY_TIMEOUT=2400 ~/ovvi-docs/heavy.sh ~/ovvi-docs/gui-free.sh env DERIVED_DATA=/tmp/ovvi-dd-onboarding
scripts/record-onboarding.sh`, or, when the user records it, under their own hold of the GUI lock. The clips go into
`Ovvi/Onboarding/Clips`. The films, and a copy of the clips with a still of each, go into
`.build/onboarding/`. Commit the clips.

The pictures are sharp on a 4K screen because the script films at 2x on any Mac:

- It makes a display that exists only in software (`hidpi-display.m`, the private `CGVirtualDisplay` API of
  CoreGraphics): 3840 x 2160 pixels at 2x, so 1920 x 1080 pt, at 60 Hz. While the script runs, that display is the
  main display: the scene's windows, the menu bar and the Dock go to it, and other windows stay where they are. At
  the end the display goes, and macOS puts the screens back as they were.
- Each clip films the 1200 x 800 pt window at 2400 x 1600 pixels. The welcome shows it at 960 x 640 pt, which is
  1920 x 1280 pixels on a 2x screen (a 4K screen at its default size too), so the clip is encoded at that size.
  HEVC at CRF 18 keeps the text of the terminals sharp, at about 1.6 times the size of CRF 24. `CRF=<n>` changes
  it.
- The films show the welcome panel at 2x (2048 x 1408 pixels, 60 fps): sharp at their own size on a 4K screen. A
  film at full screen on a 4K screen is enlarged, and not sharp: macOS draws at 2x at most.
