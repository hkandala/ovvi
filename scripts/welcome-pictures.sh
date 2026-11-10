#!/usr/bin/env bash
# v5's welcome pictures (Ovvi/Onboarding/Welcome.xcassets): the shared scene (welcome-scene.sh) in a 1320 x 590 pt
# window, built up in five stages, dark then light, then cut into the pieces `Piece` in WelcomeScene.swift places.
#   5  first: the docs space, its Markdown card turned into Browser on the dev server, the sidebar closed: the other
#      machine's window. Then the space goes, so This Mac's sidebar below does not list it.
#   1  the Server tab, the dev server's pane zoomed: one pane
#   2  the zoom undone (the dev server | npm test), then npm test's own Split Down: a pane asking what it runs
#   3  the sidebar open: the tab bar and the spaces
#   4  the Dark mode tab: Claude Code at work in Chat | Git, the uncommitted diff
# `shoot` holds the GUI lock's work (playbook/workflow.md: the app takes clicks) and leaves the shots in
# /tmp/p57y5-shots; `cut` makes the catalog from them. Usage: scripts/welcome-pictures.sh shoot [dark|light] | cut
set -euo pipefail
cd "$(dirname "$0")/.."
scene=${SCENE:-scripts/welcome-scene.sh} world=p57y5 W=/tmp/p57y5 shots=/tmp/p57y5-shots
out=Ovvi/Onboarding/Welcome.xcassets

if [ "${1:-}" = shoot ]; then
    mkdir -p $shots
    herdr=$(command -v herdr)
    for look in ${2:-dark light}; do
        trap '$scene down $world acme' EXIT
        trap 'exit 1' INT TERM HUP
        $scene up $world acme $look 1320x590
        source $W/scene.env
        h() { env -i HOME="$R" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$W/xdg" "$herdr" --session "$S" "$@"; }
        panes() { h pane list --workspace "$1" | python3 -c 'import json, sys
print(*[p["pane_id"] for p in json.load(sys.stdin)["result"]["panes"] if p["tab_id"] == sys.argv[1]])' "$2"; }
        click() { $scene click $world "$1" && sleep "${2:-1.5}"; }
        # The docs space's pi and Markdown card: the card shows Browser (its Open With would name this Mac's app).
        read -r _ md < <(panes w3 w3:t1)
        (cd "$R/docs" && env -i HOME="$R" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$W/xdg" HERDR_SESSION="$S" \
            HERDR_BIN_PATH="$herdr" HERDR_PANE_ID="$md" sh "$R/.cache/ovvi/bin/ovvi" open browser \
            "http://localhost:$port/" --replace "$md" >/dev/null)
        click w3 3
        click titlebar.sidebar 2
        $scene shot $world 5 >/dev/null
        h workspace close w3 >/dev/null
        # The Server tab's two panes: the dev server, npm test.
        read -r server tests < <(panes w1 w1:t3)
        click w1:t3
        click "pane.$server.zoom" 2.5
        $scene shot $world 1 >/dev/null
        click "pane.$server.zoom" 2.5
        # Its buttons show on the card with the keyboard.
        click "pane.$tests" 1
        click "pane.$tests.split-down" 2.5
        $scene shot $world 2 >/dev/null
        click titlebar.sidebar 2
        $scene shot $world 3 >/dev/null
        click w1:t2 2.5
        $scene shot $world 4 >/dev/null
        cp $W/shots/*.png "$shots/"
        $scene down $world acme
        trap - EXIT
    done
    exit 0
fi
[ "${1:-}" = cut ] || { echo "usage: $0 shoot|cut" >&2 && exit 2; }

# Each piece: its name, its shot, its frame in the window (points, as in `Piece`); kept at the screenshots' 2x, so
# the scene's zoom (up to 1.5 of 2/3) still has 2 pixels a drawn point.
swiftc -O -o $shots/cut scripts/welcome-cut.swift
rm -rf $out && mkdir -p $out
echo '{"info":{"author":"xcode","version":1}}' >$out/Contents.json
while read -r name shot x y w h; do
    set=$out/welcome.$name.imageset
    mkdir -p "$set"
    for look in dark light; do
        $shots/cut "$shots/$shot-$look.png" "$x" "$y" "$w" "$h" "$set/$name-$look.heic"
    done
    printf '%s\n' '{"images":[' "{\"filename\":\"$name-light.heic\",\"idiom\":\"universal\"}," \
        "{\"appearances\":[{\"appearance\":\"luminosity\",\"value\":\"dark\"}],\"filename\":\"$name-dark.heic\",\"idiom\":\"universal\"}" \
        '],"info":{"author":"xcode","version":1}}' >"$set/Contents.json"
done <<'EOF'
1a 1 8 46 1304 536
2a 2 8 46 648 536
2b 2 664 46 648 264
2c 2 664 318 648 264
3a 3 300 46 502 536
3b 3 810 46 502 264
3c 3 810 318 502 264
3s 3 0 46 296 544
3t 3 296 0 1024 46
4a 4 300 46 502 536
4b 4 810 46 502 536
4s 4 0 46 296 544
4t 4 296 0 1024 46
5r 5 0 46 1320 544
EOF
du -sh $out
