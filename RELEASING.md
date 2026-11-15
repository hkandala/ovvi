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
3. **Bump changed default plugins.** A default plugin whose source changed since the last tag needs a higher version in
   its `package.json` (`git diff --stat <last tag> -- plugins/builtin`). The app replaces an unedited copy with a
   newer version at launch ([Packages](docs/content/docs/plugins/packages.mdx)).
4. **Write the notes and tag.** Use an annotated tag. Its message opens the notes: the highlights, in your words. The
   script adds the `feat` subjects since the last release, then the `fix` and `perf` subjects, folded.

   ```sh
   git tag -a v0.2.0 -m "The highlights" && git push origin v0.2.0
   ```

   A lightweight tag (GitHub's web form makes one) opens the notes with its commit's subject instead.
5. **Watch the run.**
   `gh run watch $(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')`.
   Then open the release page and check the zip, `SHA256SUMS`, `appcast.xml` and the notes.
6. **Check the install.** In the Tart VM (a clean Mac), run the curl line below (with `-s -- --version <version>` for a
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

- **Private key:** the GitHub secret `SPARKLE_PRIVATE_KEY` of the `release` environment, and a copy in the user's
  password manager. Only the publish job reads it.
- **Public key:** `SUPublicEDKey` in `Ovvi/Info.plist`.
- If the private key is lost, installed apps can take no more updates. Make a new key pair, put the new public key in
  `Info.plist`, and tell users to install again with the curl line.

## Install a release

```sh
curl -fsSL https://github.com/hkandala/ovvi/releases/latest/download/install.sh | sh
```

Add `-s -- --version 0.2.0` after `sh` for one release. The script checks the zip against `SHA256SUMS`, puts
`Ovvi.app` in `/Applications` (or `~/Applications`) in place of an old copy, and opens the app. It asks before it links
the `ovvi` skill for Claude Code, Codex, Pi and OpenCode (to the app's own copy, so updates update it), and before it
installs herdr and its agent integrations. curl adds no quarantine flag, so Gatekeeper never asks.

## Dev builds

```sh
git pull && make install
```

This builds **Ovvi Dev** from the checkout and puts it in `~/Applications`, beside Ovvi. Ovvi Dev has its own name,
bundle id (`dev.ovvi.app.dev`), `ovvi-dev://` scheme, settings and folders (`~/.config/ovvi-dev`), and a blueprint
icon (`AppIconDev`; `make icons` draws it with `scripts/dev-icon.swift`). It has no update feed: run the same line
again to update it. `make install` also links the `ovvi` skill to the checkout's `skills/ovvi`, unless a skill is
already there.

## Plugins
