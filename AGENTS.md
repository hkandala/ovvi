# AGENTS.md

Ovvi: a native SwiftUI client for herdr on macOS.

## What to read

- The docs in `docs/content/docs/` (published at ovvi.dev/docs) say what the app does. They win on behavior.
- `playbook/workflow.md`: for the orchestrator, who plans, briefs agents and runs the tests and CI.
- `playbook/lessons.md`: before a big change, and when troubleshooting.
- `RELEASING.md`: for any release (an app tag or a plugin version), follow its checklist and verify each item.
- `~/ovvi-docs/`: everything outside the repo (this Mac's facts in `brief.md`, the phases, scratch space).

## The rules that never bend

- The simplest code that works: no speculative abstractions, no "for later" code, no compat code.
- Comments only where the code cannot say it (an assumption, a reason that is not visible). No comments that repeat
  the code.
- A test must be worth keeping: it checks behavior a user or caller relies on, and it fails without the change.
  Show it red on the old code before you call it proof.
- `make lint build test` on the rebased tree before you push. Never `git commit --no-verify`, never `git stash`.
- herdr: the user's sessions are read only. Write only to throwaway sessions `ovvi-e2e-*` / `ovvi-dev-*`
  and delete them after. Every herdr argv carries `--session`; never call herdr focus methods.
- A rule a tool can check gets a lint rule or a script, not a line here.
