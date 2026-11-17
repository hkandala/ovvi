# Releasing Ovvi

## What a release is

A release is a version tag on main, such as `v0.2.0`. When the tag is pushed, `.github/workflows/release.yml`:

1. Checks that the tagged commit is on main, then runs `make lint test`.
2. Builds `make zip`: the Release app, ad-hoc signed, with Hardened Runtime off. The tag is the version people see
   (`v0.2.0` is 0.2.0). The build number is main's commit count (`git rev-list --count`), so it only grows.
3. Publishes a GitHub Release with `Ovvi-<version>.zip`, `SHA256SUMS`, `install.sh` and `appcast.xml`, the update feed
   of Sparkle (the app's updater). Its notes come from `scripts/release-notes.sh`.

The build job holds no secret. The publish job (Ubuntu, the `release` environment) signs the zip with the Sparkle key
(`scripts/appcast.sh`) and runs only the tag's own scripts. A tag with a suffix (`v0.2.0-rc.1`) makes a pre-release:
GitHub's "latest" skips it, so neither `install.sh` nor the apps' update checks see it.

A local `make zip` builds the same app, stamped with the nearest `v*` tag behind HEAD.

## Cut a release

1. **Pick the version.** Before 1.0: a release with a `feat` commit since the last one raises the minor number
   (`v0.2.0` to `v0.3.0`); a release of fixes only raises the patch number (`v0.3.0` to `v0.3.1`). Never publish a
   version number twice.
2. **Check main.** A full run and the on-demand tests on the commit, both green ([ci.md](playbook/ci.md#running-part-of-it)):
   `gh workflow run ci.yml --ref main` and `gh workflow run ci.yml --ref main -f on_demand=true`.
3. **Write the notes and tag.** Use an annotated tag. Its message opens the notes: the highlights, in your words. The
   script adds the `feat` subjects since the last release, then the `fix` and `perf` subjects, folded.

   ```sh
   git tag -a v0.2.0 -m "The highlights" && git push origin v0.2.0
   ```

   A lightweight tag (GitHub's web form makes one) opens the notes with its commit's subject instead.
4. **Watch the run.**
   `gh run watch $(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')`.
   Then open the release page and check the zip, `SHA256SUMS`, `appcast.xml` and the notes.
5. **Check the install.** In the Tart VM (a clean Mac), run the curl line below (with `-s -- --version <version>` for a
   pre-release). The app must open with no Gatekeeper dialog.

## Fix a failed release

- **The run failed.** A failed run publishes nothing. Fix the cause on main, move the tag to the fixed commit and push
  it again. The workflow runs again:

  ```sh
  git tag -f -a v0.2.0 -m "The highlights" && git push -f origin v0.2.0
  ```

- **The release is out, but broken.** People may have installed it, so do not reuse its number. Fix it on main and cut
  the next patch version (`v0.2.1`).
- **A test release.** Delete it with its tag: `gh release delete <tag> --cleanup-tag --yes`.

## The Sparkle key

Sparkle checks each update's EdDSA signature before it installs it. Ad-hoc apps have no stable code signature, so
this key is what the app trusts.

- **Private key:** the GitHub secret `SPARKLE_PRIVATE_KEY` of the `release` environment, and a copy in the maintainer's
  password manager. Only the publish job reads it.
- **Public key:** `SUPublicEDKey` in `Ovvi/Info.plist`.
- If the private key is lost, installed apps can take no more updates. Make a new key pair, put the new public key in
  `Info.plist`, and tell users to install again with the curl line.

## Install a release

```sh
curl -fsSL https://github.com/hkandala/ovvi/releases/latest/download/install.sh | sh
```

Add `-s -- --version 0.2.0` after `sh` for one release, a pre-release too. What the script does:
[Install](https://ovvi.dev/docs#install). Dev builds (`make install`, Ovvi Dev):
[README.md](README.md#build-from-source).

## Plugins

`.github/workflows/plugins.yml` publishes three packages to npm, apart from app releases:

| Package | Folder |
|---|---|
| `@ovvi/plugin-api` | `web/ovvi/` (only `ovvi.d.ts`) |
| `@ovvi/explorer` | `plugins/builtin/explorer/` (`dist/` and `places.json`) |
| `@ovvi/git` | `plugins/builtin/git/` (`dist/`) |

It runs on a push to main that touches `plugins/builtin/**` or the types, and on a dispatch. For each package whose
`version` npm does not have, it runs `npm ci` and `npm run build`, then `npm publish` through npm's trusted publishing:
no token, and npm adds provenance. A package that is not on npm at all is skipped with a warning.

**Release a plugin:** bump its `version` in its `package.json` (every change to a plugin's source does) and push to
main. Users see "Update to ‹version›" on the plugin's page in Settings ▸ Plugins. A version for a newer plugin API
(`ovvi.api`) is refused by older apps, so bump `api` only with the app release that brings it.

**Set up once.** Trusted publishing cannot make a package, and `npm trust` needs the package to exist, so each name gets
one placeholder by hand:

1. On npmjs.com, sign in, turn on two-factor authentication (Account ▸ Two-Factor Authentication), then avatar ▸
   **Add Organization**: name `ovvi`, the free plan (unlimited public packages). It owns the `@ovvi` scope.
2. On the Mac, with npm 11.15 or later (`npm install -g npm@latest`): `npm login`, then publish the placeholders:

   ```sh
   for name in @ovvi/plugin-api @ovvi/explorer @ovvi/git; do
     dir=$(mktemp -d)
     printf '{"name":"%s","version":"0.0.0","description":"Placeholder"}' "$name" > "$dir/package.json"
     npm publish "$dir" --access public
   done
   ```

3. Trust the workflow for each (2FA asks once):

   ```sh
   for name in @ovvi/plugin-api @ovvi/explorer @ovvi/git; do
     npm trust github "$name" --file plugins.yml --repo hkandala/ovvi --allow-publish --yes
     sleep 2
   done
   ```

4. Within 2 days (an unused trusted publisher expires): `gh workflow run plugins.yml --ref main`. It publishes the
   current versions with provenance.
5. Then, for each name: `npm deprecate <name>@0.0.0 "placeholder"`, and on npmjs.com the package's Settings ▸
   Publishing access ▸ **Require two-factor authentication and disallow tokens**.
