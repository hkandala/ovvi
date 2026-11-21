# Releasing Ovvi

Two things ship, each on its own: the app (a version tag) and the plugins on npm (a version bump on main).

## The app

### What a tag does

A tag `vX.Y.Z` on main runs `.github/workflows/release.yml`:

1. Checks that the commit is on main, then runs `make lint test`.
2. Builds `make zip`: the Release app, ad-hoc signed. The tag is the version people see; the build number is main's
   commit count (`git rev-list --count`), so it only grows.
3. Publishes a GitHub Release with `Ovvi-<version>.zip`, `SHA256SUMS`, `install.sh` and `appcast.xml`.

A tag with a suffix (`v0.2.0-rc.1`) makes a pre-release, which `install.sh` and the apps' update checks skip.

### Cut a release

1. **Pick the number.** Patch (`0.1.1` to `0.1.2`) for most releases, minor (`0.1` to `0.2`) for a big change. Never
   reuse a number, even one whose release was deleted.
2. **Check main:** a full CI run and the on-demand tests, both green on the commit
   ([ci.md](playbook/ci.md#running-part-of-it)).
3. **Tag it.** The tag's message opens the release notes (the highlights); `scripts/release-notes.sh` adds the `feat`,
   `fix` and `perf` subjects since the last release.

   ```sh
   git tag -a v0.1.2 -m "The highlights" && git push origin v0.1.2
   ```

4. **Watch it:** `gh run watch $(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')`.
   Then check the release page's assets and notes, and install it in the Tart VM (below): it must open with no
   Gatekeeper dialog.

**A failed run** publishes nothing: fix main, then move the tag (`git tag -f -a … && git push -f origin <tag>`).
**A broken release** that is out: fix main and cut the next patch.

### How users get it

- **New install:** `curl -fsSL https://github.com/hkandala/ovvi/releases/latest/download/install.sh | sh` (add
  `-s -- --version <version>` for one release). It checks `SHA256SUMS`, replaces `Ovvi.app` and offers herdr and the
  skill.
- **Updates (Sparkle):** the app reads `releases/latest/download/appcast.xml` once a day (Settings ▸ General) or on
  Ovvi ▸ Check for Updates…, shows a notice, and installs on Update…. Sparkle installs only a zip signed with the
  release key (below).

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

### Update a default plugin

1. Change it and bump its `version` in `package.json` and `package-lock.json` (`make lint` checks that a changed
   plugin has a new version).
2. Push to main. The workflow publishes it in a few minutes.

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
