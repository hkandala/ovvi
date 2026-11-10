#!/usr/bin/env bash
# The welcome tour's pictures (Ovvi/Onboarding/Welcome.xcassets), taken from the shared scene (welcome-scene.sh) in
# both looks: main (shortlink's Link expiry tab), split (a new pane at its chooser below the chat), agents (Dark
# mode: Claude Code at work beside Git), plugins (Files: File Explorer beside a plugin of the user's own, CI Runs, made
# with New Plugin's template) and machines (the machine menu). Hold the GUI lock while it runs (about 3 minutes).
# Usage: scripts/welcome-pictures.sh   (Ovvi Dev built at $DERIVED_DATA, default /tmp/ovvi-dd-p57y3)
set -euo pipefail
cd "$(dirname "$0")/.."
unset "${!HERDR_@}"
world=p57y3 session=projects W=/tmp/p57y3 out=${TMPDIR:-/tmp}/welcome-pictures
export DERIVED_DATA=${DERIVED_DATA:-/tmp/ovvi-dd-p57y3}
scene() { scripts/welcome-scene.sh "$1" "$world" "${@:2}"; }
mkdir -p "$out"
# A running window recorder puts macOS's capture indicator in place of the window's buttons.
if pgrep -fl record-window; then echo "a window recorder runs: no pictures now" >&2 && exit 1; fi
swiftc -O -o "$out/heic" scripts/welcome-heic.swift

# herdr and ovvi in the scene's session, as its scripts run them.
HERDR=$(command -v herdr)
h() { env -i HOME="$H" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$W/xdg" "$HERDR" --session "$session" "$@"; }
o() {
    local pane=$1
    shift
    (cd "$H/shortlink" && env -i HOME="$H" PATH="$(dirname "$(command -v node)"):/usr/bin:/bin" \
        XDG_CONFIG_HOME="$W/xdg" HERDR_SESSION="$session" HERDR_BIN_PATH="$HERDR" HERDR_PANE_ID="$pane" \
        npm_config_cache="$HOME/.npm" npm_config_prefer_offline=true sh "$H/.cache/ovvi/bin/ovvi" "$@")
}
panes() { h pane list --workspace w1 | python3 -c "import json, sys
print(*[p['pane_id'] for p in json.load(sys.stdin)['result']['panes'] if p['tab_id'] == '$1'])"; }

for look in dark light; do
    scene up "$session" "$look"
    H=/Users/Shared/welcome-scene/$world
    source "$W/scene.env"
    trap 'scene down "$session"' EXIT
    scene shot main >/dev/null
    # A new pane below the chat (the card with the keyboard shows its buttons) asks what it runs; then it goes again.
    browser=$(panes w1:t1 | tr ' ' '\n' | grep -vx "$c1")
    scene click "pane.$c1.split-down"
    sleep 2
    scene shot split >/dev/null
    for p in $(panes w1:t1); do [ "$p" = "$c1" ] || [ "$p" = "$browser" ] || h pane close "$p" >/dev/null; done
    scene click w1:t2
    sleep 2
    scene shot agents >/dev/null
    # CI Runs: New Plugin's template with a run list in it, beside README.md in File Explorer.
    files=$(panes w1:t5)
    o "$files" --timeout 180 plugins new "CI Runs" >/dev/null
    plugin=$W/config/plugins/ci-runs
    cp scripts/welcome-pictures/ci-runs/* "$plugin/src/"
    cp scripts/welcome-pictures/ci.json "$H/shortlink/ci.json"
    python3 - "$plugin/package.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1]))
manifest["description"] = "The runs in a ci.json file."
manifest["ovvi"].update({"icon": "checklist", "opens": {"files": ["ci.json"], "priority": "default"},
                         "header": [{"id": "summary", "type": "text", "style": "dim"}]})
manifest["ovvi"].pop("settings", None)
json.dump(manifest, open(sys.argv[1], "w"), indent=2)
PY
    o "$files" --timeout 120 plugins reload ci-runs >/dev/null
    o "$files" open ci-runs ./ci.json --beside "$files" >/dev/null
    scene click w1:t5
    sleep 2
    # The notice of a card an agent opened ("… opened CI Runs"): not in the picture.
    scene click notice.close
    sleep 1.5
    scene shot plugins >/dev/null
    scene click w1:t1
    sleep 1
    scene click titlebar.machine
    sleep 1.5
    scene shot machines >/dev/null
    cp "$W"/shots/*.png "$out/"
    trap - EXIT
    scene down "$session"
done

catalog=Ovvi/Onboarding/Welcome.xcassets
for name in main split agents plugins machines; do
    set=$catalog/welcome-$name.imageset
    rm -rf "$set" && mkdir -p "$set"
    for look in light dark; do
        "$out/heic" "$out/$name-$look.png" "$set/$name-$look.heic" 0.9 1800
    done
    cat >"$set/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "$name-light.heic", "idiom" : "universal", "scale" : "2x" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "$name-dark.heic",
      "idiom" : "universal", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
done
du -sh "$catalog"
