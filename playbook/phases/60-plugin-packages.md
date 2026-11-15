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
