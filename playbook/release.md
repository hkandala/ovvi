# Releases

A version tag on main publishes a release: `.github/workflows/release.yml` checks that the tag is on main, runs
`make lint test`, builds `make zip` (the Release app, ad-hoc signed, Hardened Runtime off) and publishes a GitHub
Release with `Ovvi-<version>.zip`, `SHA256SUMS`, `install.sh`, the notes of `scripts/release-notes.sh` and
Sparkle's feed, `appcast.xml` (`scripts/appcast.sh`). The build job holds no secret; the publish job (Ubuntu, the
`release` environment) signs the zip with `SPARKLE_PRIVATE_KEY` and runs only the tag's own scripts. The tag sets the version
(`v0.2.0` is 0.2.0); the build number is main's commit count (`git rev-list --count`). A local `make app` stamps
the same two values from the nearest `v*` tag behind HEAD, so a build at the tag matches the release. A tag with a suffix (`v0.2.0-rc.1`) makes a pre-release, which
GitHub's "latest" skips.

## Before a tag

1. A full run and the on-demand tests on the commit, both green ([ci.md](ci.md#running-part-of-it)):
   `gh workflow run ci.yml --ref main` and `gh workflow run ci.yml --ref main -f on_demand=true`.
2. A default plugin whose source changed since the last tag gets a higher version in its `package.json`
   (`git diff --stat <last tag> -- plugins/builtin`): an app with a newer version replaces an unedited copy at launch
   ([Packages](../docs/content/docs/plugins/packages.mdx)).

## Tag

An annotated tag: its message opens the notes (the highlights, in your words), then the `feat` subjects since the
last release, then the `fix` and `perf` subjects, folded. A lightweight tag (GitHub's web
form makes one) opens the notes with its commit's subject instead.

```sh
git tag -a v0.2.0 -m "The highlights" && git push origin v0.2.0
```

## Check

- `gh run watch $(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')`, then the
  release page: the zip, `SHA256SUMS`, the notes.
- Install it on a clean Mac (the Tart VM) and open it once.

A failed run publishes nothing: fix it on main, move the tag (`git tag -f -a`, `git push -f origin <tag>`), and it
runs again. To drop a test release: `gh release delete <tag> --cleanup-tag --yes`.

## Dev builds

Ovvi Tip is the dev build of any commit since it came (an older one stops the run): `gh workflow run tip.yml` (main) or `gh workflow run tip.yml -f ref=<sha,
branch or tag>`. It replaces the rolling pre-release `tip` (its notes name the commit) with `Ovvi-Tip.zip` and
`SHA256SUMS`. The app is `Ovvi Tip.app`, `dev.ovvi.app.tip`, with a DEV badge on its icon, and keeps its own settings
and folders, so it runs beside Ovvi ([Data](../docs/content/docs/data.mdx)). Locally: `make zip TIP=1`.

It runs only on a dispatch: a build holds one of the 5 macOS runners for about 6 minutes, and main gets dozens of
pushes a day, so a build per push would double what pushes cost and take runners from full runs.

The `tip` tag moves with each build: `git fetch --tags` refuses it, `git fetch --tags --force` takes it. Build Tips
from main: a branch's commit count can be higher than later main Tips', and Sparkle offers a Tip only a higher one.
