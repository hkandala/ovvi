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
