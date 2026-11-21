# Releasing Ovvi

Two things ship, each on its own: the app (a version tag) and the plugins on npm (a version bump on main).

## What Ovvi connects to

| System | What for | Where it is set |
|---|---|---|
| GitHub Releases | the zip, `install.sh` and Sparkle's `appcast.xml` | `release.yml`; the feed URL in the `Makefile` (`zip`) |
| Sparkle | the released app's updates | `SUFeedURL` and `SUPublicEDKey` in `Ovvi/Info.plist`; the private key in the `release` environment |
| PostHog (EU), through `e.ovvi.dev` | anonymous usage counts from the released app | the key in the `Makefile` (`zip`); the endpoint in `HerdrKit/Usage.swift` |
| npm | publishing `@ovvi/*`; installing and updating plugins (the user's npm) | `plugins.yml` (trusted publishing); the app runs the user's npm, pnpm or bun |
| herdr.dev | herdr's install script, offered by `install.sh` and the app | `install.sh`; `Ovvi/Store/HerdrInstall.swift` |
| Vercel | the docs site, ovvi.dev | `docs-deploy.yml` on a push to main; secrets `VERCEL_*` |
| skills.sh | lists the `ovvi` skill from this repo | nothing to set: it reads GitHub |

The browser card's search goes to Google. Nothing else leaves the Mac except the user's own SSH to remote machines.

## The app

### What a tag does

A tag `vX.Y.Z` on main runs `.github/workflows/release.yml`:

1. Checks that the commit is on main, then runs `make lint test`.
2. Builds `make zip`: the Release app, ad-hoc signed. The tag is the version people see; the build number is main's
   commit count (`git rev-list --count`), so it only grows.
3. Publishes a GitHub Release with `Ovvi-<version>.zip`, `SHA256SUMS`, `install.sh` and `appcast.xml`.

A tag with a suffix (`v0.2.0-rc.1`) makes a pre-release, which `install.sh` and the apps' update checks skip.

### App release checklist

- [ ] **Number:** patch (`0.1.1` to `0.1.2`) for most releases, minor (`0.1` to `0.2`) for a big change. Never reuse
  a number, even one whose release was deleted.
- [ ] **Main is green:** a full CI run and the on-demand tests on the commit
  ([ci.md](playbook/ci.md#running-part-of-it)).
- [ ] **Notes written** (below) and read once more as a user would.
- [ ] **Tagged:** `git tag -a v0.1.2 -F notes.md && git push origin v0.1.2`.
- [ ] **Run watched:**
  `gh run watch $(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')`.
- [ ] **Release checked:** it is GitHub's latest; the zip, `SHA256SUMS`, `install.sh` and `appcast.xml` are there; the
  zip's checksum matches; `appcast.xml` names the new version.
- [ ] **Installed:** the install line in the Tart VM opens the app with no Gatekeeper dialog, and an older app offers
  the update (Ovvi ▸ Check for Updates…).

### Release notes

The tag's message is the notes: its first line is the title line, the rest the body. `scripts/release-notes.sh`
then adds the `feat` subjects and, folded, the `fix` and `perf` subjects since the last release.

- Write for users: what they can do now or what works better, not how it was built.
- One summary sentence, then 3–8 bullets, most important first. One change per bullet.
- Name things as the app does: menu items, settings and keys (Settings ▸ General, ⌘K).
- Say what a user must do, if anything (a setting that moved, a one-time reset).
- No internal names: no commit scopes, file names, symbols or track names.

**A failed run** publishes nothing: fix main, then move the tag (`git tag -f -a … && git push -f origin <tag>`).
**A broken release** that is out: fix main and cut the next patch.

### How users get it

- **New install:** `curl -fsSL https://github.com/hkandala/ovvi/releases/latest/download/install.sh | sh` (add
  `-s -- --version <version>` for one release). It checks `SHA256SUMS`, replaces `Ovvi.app` and offers herdr and the
  skill.
- **Updates (Sparkle):** the app reads `releases/latest/download/appcast.xml` once a day (Settings ▸ General) or on
  Ovvi ▸ Check for Updates…, shows a notice, and installs on Update…. Sparkle installs only a zip signed with the
  release key (below).

### Dev builds

`make install` builds **Ovvi Dev** (`dev.ovvi.app.dev`) from the checkout into `~/Applications`. It has no update
feed and no PostHog key, and it records the checkout's path, so Settings ▸ General ▸ Rebuild runs `make install`
from it again (a log window, then Ovvi Dev reopens). Debug builds and `make app` have neither feed, key nor
Rebuild.

### PostHog

- **Key:** the project key (`phc_…`) is in the `Makefile`'s `zip` target, so only the released app has it. A project
  key can only send events, never read them, so it is not a secret.
- **Where it goes:** `https://e.ovvi.dev/batch/`, a DNS name for PostHog's managed proxy (EU). No server of ours.
- **What:** one `app_day` event a day: the version, macOS and which features were used. No IP, no person profile,
  no names or paths.
- **Off:** Settings ▸ Privacy, or `OVVI_TELEMETRY=0` or `DO_NOT_TRACK=1` in the login shell. Help ▸ Usage Data Log
  shows what was sent.

### The Sparkle key

Ad-hoc apps have no stable code signature, so Sparkle trusts an EdDSA key instead.

- **Private:** the secret `SPARKLE_PRIVATE_KEY` of the `release` environment (only the publish job reads it), with a
  copy in the maintainer's password manager.
- **Public:** `SUPublicEDKey` in `Ovvi/Info.plist`.
- If the private key is lost, installed apps take no more updates: make a new pair, put the public key in
  `Info.plist`, and tell users to run the install line again.

## The skill

The `ovvi` skill lives in `skills/ovvi/` and ships inside the app (`Ovvi.app/Contents/Resources/skills/ovvi`).

- **Installed by `install.sh`:** `~/.agents/skills/ovvi` and `~/.claude/skills/ovvi` are links into `Ovvi.app`, so
  each app update replaces the skill with the release's copy. Edits there are lost. The script links only when no
  `ovvi` skill is there, so it never replaces one you installed another way.
- **Installed with `npx skills add hkandala/ovvi -g`** (other agents, remote machines): a copy from main.
  `npx skills update` brings the newest; app updates do not touch it.

So a skill change ships with the next app release, and to `npx` users as soon as it is on main.

## Plugins on npm

`.github/workflows/plugins.yml` publishes `@ovvi/plugin-api` (`web/ovvi/`), `@ovvi/explorer` and `@ovvi/git`
(`plugins/builtin/`). It runs on a push to main that touches them, on every release tag, and on a dispatch. It
publishes each version npm does not have yet, through npm's trusted publishing: no token, with provenance.

### Plugin release checklist

- [ ] **Version bumped** in `package.json` and `package-lock.json`: patch for fixes, minor for new features, major
  when settings or behaviour change incompatibly (`make lint` checks that a changed plugin has a new version).
- [ ] **`ovvi.api`** raised only together with the app release that brings that API.
- [ ] **README** still true (what it does, how to install).
- [ ] **Pushed to main;** the `plugins` run is green and lists `+ <name>@<version>`.
- [ ] **On npm:** `npm view <name> version` shows it, with provenance.
- [ ] **In Ovvi:** on an app with the old version, the plugin's page in Settings ▸ Plugins shows Update to
  ‹version›.

Users get it two ways:

- **From npm:** the plugin's page in Settings ▸ Plugins shows Update to ‹version›.
- **With the app:** at launch, an app whose bundled copy is newer than the installed one replaces it, edits included.

Bump the plugin's `ovvi.api` only with the app release that brings that API: older apps refuse the plugin.

### A new package under `@ovvi`

1. Add its folder to the loop in `plugins.yml`.
2. Publish its first version by hand (trusted publishing cannot create a package): `npm publish --access public`
   in its folder, with your npm 2FA.
3. Trust the workflow, then require 2FA and disallow tokens on its npm page (Settings ▸ Publishing access):

   ```sh
   npm trust github @ovvi/<name> --file plugins.yml --repo hkandala/ovvi --allow-publish --yes
   ```

### Anyone's plugin

A plugin is an npm package with an `ovvi` manifest in its `package.json`
([Create a plugin](https://ovvi.dev/docs/plugins/create)). Publish it with `npm publish --access public`, with the
keyword `ovvi-plugin`. Users install it in Settings ▸ Plugins with `npm:<package>`, and see Update to ‹version›
when you publish a newer one.
