#!/usr/bin/env bash
# Makes the welcome's pictures (Ovvi/Onboarding/Pictures) from the shared scene, dark then light: the 1280 x 800 pt
# window at 2x, HEIC at quality 90. Hold the GUI lock while it runs (playbook/workflow.md); Ovvi Dev comes from
# $DERIVED_DATA (scripts/welcome-scene.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
world=welcome-pictures out=/tmp/welcome-pictures-shots
scene() { scripts/welcome-scene.sh "$1" "$world" "${@:2}"; }
trap '[ -d /tmp/$world ] && scene down work' EXIT
mkdir -p "$out"
for look in dark light; do
    scene up work "$look" 1280x800
    # The tabs' bounce settles first.
    sleep 10
    scene shot overview
    scene click w1:t2
    sleep 3
    scene shot chat
    scene click w3
    sleep 3
    scene shot docs
    scene click w1
    scene click w1:t3
    sleep 3
    scene shot server
    # The right pane, split down: its chooser.
    right=$(env -i HOME="/Users/Shared/welcome-scene/$world" PATH=/usr/bin:/bin XDG_CONFIG_HOME="/tmp/$world/xdg" \
        "$(command -v herdr)" --session work pane list |
        python3 -c 'import json, sys; print([p["pane_id"] for p in json.load(sys.stdin)["result"]["panes"]
            if p["tab_id"] == "w1:t3"][-1])')
    scene click "pane.$right"
    sleep 1
    scene click "pane.$right.split-down"
    sleep 3
    scene shot splitdown
    scene click w1:t1
    sleep 3
    scene click titlebar.machine
    sleep 2
    scene shot machines
    cp /tmp/$world/shots/*.png "$out/"
    scene down work
done
for png in "$out"/*.png; do
    sips -s format heic -s formatOptions 90 "$png" --out "Ovvi/Onboarding/Pictures/welcome-$(basename "$png" .png).heic" >/dev/null
done
du -ch Ovvi/Onboarding/Pictures/*.heic | tail -1
