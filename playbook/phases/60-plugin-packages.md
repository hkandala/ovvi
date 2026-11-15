# Phase 60: the default plugins on npm

## The user's words

"for the plugins, we should publish each default plugin as npm packages as well, so plugins can update indepentally,
and individual plugin should have update option as well, which basically runs npm upgrade, and for plugins, right
reload all doesn't do build right, i think it should also rebuild them when reload all is pressed, so for plugins this
is how it works right, user can eitehr install from npm package, if they install from npm package we downlaod it,
build it and then have options to updarte which checks the npm package verisons, if they install through other
sources like git repo or file path, then we build it, but won't show update options"

The plan the user approved ("plugin plan sounds good"):
1. Publish File Explorer, Git and `@ovvi/plugin-api` to npm under `@ovvi`.
2. A workflow publishes a plugin when its version on main is not on npm yet, apart from app releases.
3. The defaults become npm installs: they update on their own, not with the app.
4. Update only for npm installs: it checks npm and offers "Update to ‹version›".
5. git and local installs build but show no Update.
6. Reload All rebuilds every git and local plugin, not only those with an open card.

## Tracks

### Track N (one agent)

## Findings

### Track N

- **Decisions.** The npm names stay the packages' own: `@ovvi/explorer` and `@ovvi/git` (folder = id = the name's
  last part, so no path changed), and `@ovvi/plugin-api` from `web/ovvi` (only `ovvi.d.ts`). A default installs from
  the app's copy only while its folder is missing (first launch; `npm ci` from the network or npm's cache), and each
  launch lists `npm:@ovvi/<id>` in `settings.json` when no source of its folder is there: so an existing copy, or a
  rewritten `settings.json`, is an npm install too. No Remove.
- **Deleted.** The defaults' version and hash records (`.defaults.json`, SHA-256 of source and copy), the launch-time
  replace, Update to Version, Reset to Default, the edited-copy prompt and Trash, and git's Update.
- **The check.** `npm pack <spec> --dry-run --json` when a plugin's page opens: the same resolve as the install, and
  it works for a tarball's path, so the npm test stays offline (`npm view` answers nothing for a tarball). "Up to
  date" shows when npm has nothing newer, so a test can tell a finished check from a running one. Tests that open a
  default's page (`npm:@ovvi/explorer`) ask the real registry once it is published; offline they show nothing.
- **Versions.** With the hash check gone, a change that keeps its version never reaches npm: `make test` runs
  `scripts/check-plugin-versions.sh`, which fails for a published package changed since origin/main at its old
  version. Reload All puts failed builds on the Plugins page's notice (a plugin with no card has no toast).
- **npm installs never build again.** An npm package that ships its built entry installs no dependencies (npm packs no
  lockfile, so `npm install` would fetch every dev dependency); Reload and Reload All only load its cards again.
  Reload All builds every other plugin with code, with or without a card; `ovvi plugins reload` with no id too.
- **API gating.** An install or Update of a version whose `api` is above the app's is refused on the page's notice,
  and the installed version stays. A card of such a plugin offers Check for Updates… (the app's).
- **For the user.** npm first publish is by hand: RELEASING.md, Plugins (org `ovvi`, a 0.0.0 placeholder per name,
  `npm trust github`, then the workflow within 2 days). Until then `plugins.yml` skips each name with a warning, and
  the defaults' pages show no Update. On this Mac, `~/.config/ovvi/plugins/.defaults.json` is now unused: delete it.
- **For the user.** Edits inside an npm install are lost at Update, which asks nothing: the hash check that told an
  edit from an install is gone. Reload no longer builds a default: to change one, edit its folder, run `npm run build`
  there (a default from the app's copy has its `node_modules`), then Reload. A local copy of a default cannot load
  beside it (its id is taken).
