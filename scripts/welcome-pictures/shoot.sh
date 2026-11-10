#!/usr/bin/env bash
# The welcome's close-ups: the shared scene (scripts/welcome-scene.sh, world p57y2, session studio) in a 1200 x 760 pt
# window, shot at 2x in both looks, then cut by crop.sh into Ovvi/Onboarding/Welcome.xcassets.
# Usage (under the GUI lock, playbook/workflow.md): scripts/welcome-pictures/shoot.sh [dark light]
# The shots go to /tmp/p57y2-shots/<shot>-<look>.png; SHOTS="files plugin" takes only those.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
scene=$here/../welcome-scene.sh
out=/tmp/p57y2-shots W=/tmp/p57y2 H=/Users/Shared/welcome-scene/p57y2
mkdir -p "$out" "$out/tools"
swiftc -O -o "$out/tools/press" "$here/press.swift"
swiftc -O -o "$out/tools/wins" "$here/wins.swift"
unset "${!HERDR_@}"

shoot() {
    local look=$1
    "$scene" up p57y2 studio "$look" 1200x760
    # shellcheck disable=SC1091
    source "$W/scene.env"
    trap '"$scene" down p57y2 studio' EXIT
    ovvi() {
        (cd "$H/shortlink" && env -i HOME="$H" PATH="$(dirname "$(command -v node)"):/usr/bin:/bin" \
            XDG_CONFIG_HOME="$W/xdg" HERDR_SESSION=studio HERDR_BIN_PATH="$(command -v herdr)" HERDR_PANE_ID="$c1" \
            sh "$H/.cache/ovvi/bin/ovvi" --timeout 180 "$@")
    }
    want() { [ -z "${SHOTS:-}" ] || [[ " $SHOTS " == *" $1 "* ]]; }
    # Clicks only into the scene's window: another app in front there (the user's) is waited out.
    click() {
        for _ in 1 2 3 4 5; do "$scene" click p57y2 "$@" 2>/dev/null && return; sleep 2; done
        "$scene" click p57y2 "$@"
    }
    shot() { "$scene" shot p57y2 "$1" && cp "$W/shots/$1-$look.png" "$out/"; }
    herdr_() { env -i HOME="$H" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$W/xdg" "$(command -v herdr)" --session studio "$@"; }
    # The agents' turns play out.
    sleep 8
    # Link expiry: Claude Code's chat beside the Browser; the sidebar's spaces and the tab bar. Dark mode: Claude Code
    # beside the Git card. docs: pi beside File Explorer.
    want expiry && shot expiry
    want darkmode && click w1:t2 && sleep 3 && shot darkmode
    want files && click w3 && sleep 3 && shot files
    if want plugin; then
        # A custom plugin, as an agent makes one: New Plugin's template, then CI Runs' own code, on the repository's
        # runs, beside the notes' roadmap.
        ovvi plugins new "CI Runs" >/dev/null
        cp "$here/ci-runs/package.json" "$W/config/plugins/ci-runs/"
        cp "$here/ci-runs/src/"* "$W/config/plugins/ci-runs/src/"
        ovvi plugins reload ci-runs >/dev/null
        git -C "$H/shortlink" log -4 --format='%h %s' | python3 -c '
import json, sys
commits = [line.strip().split(" ", 1) for line in sys.stdin]
runs = [("Tests", "dark-mode", "working tree", "running", "now"), ("Tests", "main", " ".join(commits[0]), "passed",
        "1 h ago"), ("Deploy preview", "main", commits[0][0], "passed", "1 h ago"), ("Lint", "rate-limit",
        " ".join(commits[1]), "failed", "3 h ago"), ("Tests", "main", " ".join(commits[2]), "passed", "yesterday")]
print(json.dumps([dict(zip(["name", "branch", "commit", "state", "when"], run)) for run in runs], indent=2))
' >"$H/shortlink/ci.json"
        echo ci.json >>"$H/shortlink/.git/info/exclude"
        local notes
        notes=$(herdr_ pane list --workspace w5 | python3 -c 'import json, sys; print(json.load(sys.stdin)["result"]["panes"][0]["pane_id"])')
        ovvi open ./ci.json --beside "$notes" >/dev/null
        click w5 && sleep 4 && shot plugin
    fi
    # A new tab's pane, asking what it runs.
    want chooser && click titlebar.new-tab && sleep 3 && shot chooser
    if want machines; then
        # The machine menu, then Settings ▸ Machines from it.
        click titlebar.machine && sleep 1.5 && shot menu
        "$out/tools/press" "$pid" "Edit Machines…" && sleep 3
        local settings
        settings=$("$out/tools/wins" "$pid" | awk '$6 == 0 && $4 < 1000 && $4 > 500 { print $1; exit }')
        [ -n "$settings" ] || { echo "no Settings window" >&2 && exit 1; }
        screencapture -x -o -l "$settings" "$out/machines-$look.png"
    fi
    trap - EXIT
    "$scene" down p57y2 studio
}

looks=("$@")
[ ${#looks[@]} -gt 0 ] || looks=(dark light)
for look in "${looks[@]}"; do shoot "$look"; done
ls "$out"
