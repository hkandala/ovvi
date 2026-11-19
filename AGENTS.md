# AGENTS.md

Ovvi: a native SwiftUI client for herdr on macOS.

## Read first, every time

- `playbook/workflow.md`: how we work. Follow it without being told.
- `playbook/lessons.md`: problems that came back.
- The docs in `docs/content/docs/` (published at ovvi.dev/docs) say what the app does. They win on behavior.
- `~/ovvi-docs/`: everything outside the repo. `brief.md` there gives this Mac's facts, `phases/<name>/`
  holds the phases (read the ones your change touches), and `scratch/<agent>/` takes your temporary files
  (`playbook/workflow.md`, Files outside the repo).

## The rules that never bend

- Ponytail: the simplest code that works; no speculative abstractions or "for later" code.
- `make lint build test` on the rebased tree before you push, and the UI tests your change touches, never on the
  user's screen while they work: a chosen-tests CI run for existing tests, the Tart VM (`make vm-e2e`, under its
  lock) to explore; VM busy, use CI (`playbook/workflow.md`). The Mac's own screen only while the user said they are
  away, through `~/ovvi-docs/gui-free.sh` (the GUI lock). A track or a feature pushes only after its review.
  Never `git commit --no-verify`, never `git stash`.
- herdr: the user's sessions are read only. Write only to throwaway sessions `ovvi-e2e-*` / `ovvi-dev-*`
  and delete them after. Every herdr argv carries `--session`; never call herdr focus methods.
- A rule a tool can check gets a lint rule or a script, not a line here.
