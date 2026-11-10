#!/usr/bin/env bash
# Films the welcome's clips (Ovvi/Onboarding/Clips/welcome-<page>-<look>.mp4) from Ovvi Dev in the welcome pictures'
# scene (scripts/welcome-scene.sh: its own herdr world, never the user's sessions): each page brings up its tab, films
# the main window while herdr's CLI, the ovvi command and a few clicks (into Ovvi Dev's window only) make the change
# the page names, and moves a camera over the film.
# Usage: scripts/welcome-clips.sh film [dark|light|both] [pages…]   (under the GUI lock: the app runs and takes clicks)
#        scripts/welcome-clips.sh encode <page> <look>              (no lock: the films stay in $C)
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD WORLD=p57y4 S=workbench SIZE=1280x646
W=/tmp/$WORLD C=${C:-/tmp/$WORLD-clips} CLIPS=$REPO/Ovvi/Onboarding/Clips
export DERIVED_DATA=${DERIVED_DATA:-/tmp/ovvi-dd-$WORLD}
PAGES="running layout agents plugins machines"
unset "${!HERDR_@}"
HERDR=$(command -v herdr)
scene() { scripts/welcome-scene.sh "$1" $WORLD "${@:2}"; }
# Clicks an element (a space w2, a tab w1:t3, else an accessibility id) where it shows in the window: a kept page's
# copy of it can sit outside the window, where the scene's `click` refuses.
tap() {
    local id=$1 point
    [[ $id =~ ^w[0-9A-Z]+$ ]] && id=workspace.$id
    [[ $id =~ ^w[0-9A-Z]+:t[0-9A-Z]+$ ]] && id=tab.$id
    for _ in $(seq 20); do
        point=$("$W/tools/ax" "$pid" find "$id" | awk -v frame="$(window)" 'BEGIN { split(frame, w, " ") }
            { x = $2 + $4 / 2; y = $3 + $5 / 2
              if (x > w[2] && x < w[2] + w[4] && y > w[3] && y < w[3] + w[5]) { print int(x), int(y); exit } }')
        [ -n "$point" ] && break
        sleep 0.25
    done
    [ -n "$point" ] || { echo "no $id in the window" >&2 && return 1; }
    "$W/tools/ax" "$pid" front
    # shellcheck disable=SC2086 # x y
    OVVI_APP_PID=$pid "$W/tools/click" $point
}
# herdr and ovvi in the scene's session, as welcome-scene.sh has them.
h() { env -i HOME="$R" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$W/xdg" "$HERDR" --session "$S" "$@"; }
o() {
    local pane=$1 dir=$2
    shift 2
    (cd "$dir" && env -i HOME="$R" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$W/xdg" HERDR_SESSION="$S" \
        HERDR_BIN_PATH="$HERDR" HERDR_PANE_ID="$pane" sh "$R/.cache/ovvi/bin/ovvi" "$@")
}
json() { python3 -c "import json, sys; d = json.load(sys.stdin); print($1)"; }
# The panes of a tab (w1:t3), in herdr's order.
panes() { h pane list | json "'\n'.join(p['pane_id'] for p in d['result']['panes'] if p['tab_id'] == '$1')"; }
# The window's id and frame, in screen points.
window() { "$W/tools/ax" "$pid" window; }

# Films the app's windows into $C/<page>-<look>.mp4 until `wrap`, and the window's frame beside it.
roll() {
    window | cut -d' ' -f2- >"$C/$1.at"
    rm -f "$C/cue"
    mkfifo "$C/cue"
    "$C/film" "$pid" "$C/$1.mp4" <"$C/cue" >"$C/film.log" 2>&1 &
    REC=$!
    exec 3>"$C/cue"
    until grep -q recording "$C/film.log"; do sleep 0.05; done
    T0=$(python3 -c "import time; print(time.time())")
}
wrap() {
    exec 3>&-
    wait "$REC"
}
# Waits until $1 seconds after the film started: the steps keep their times however long each one takes.
upto() { sleep "$(python3 -c "import time; print(max(0, $T0 + $1 - time.time()))")"; }

# Each page: what it shows first, then the film of what changes, and the camera's keys (time:zoom:x:y as fractions
# of the film; scripts/welcome-clips/camera.py), which push in on what the page's words name.

# The work runs on: the dev server's log takes requests and the tests run again, agents work in the sidebar.
running() {
    local tests
    tap w1:t3
    tests=$(panes w1:t3 | tail -1)
    sleep 1
    roll "running-$1"
    (for path in / /style.css /app.js /api/links /api/links /k3vZ9a / /api/links /app.js /api/links; do
        curl -s -o /dev/null "http://localhost:$port$path" || true
        sleep 0.45
    done) &
    upto 1.6
    h pane run "$tests" "clear; npm test" >/dev/null
    upto 6.4
    wrap
}
running_camera="0:1:.5:.5 1:1:.5:.5 2.2:1.3:.4:.45 3:1.3:.4:.45 4.2:1.3:.78:.45 5.4:1.3:.78:.45 6.3:1:.5:.5"

# One pane grows: a split, a split down, a tab, then another space.
layout() {
    local explorer shell
    tap w5
    explorer=$(panes w5:t1 | head -1)
    sleep 1
    roll "layout-$1"
    upto 0.6
    shell=$(h pane split "$explorer" --direction right --no-focus | json "d['result']['pane']['pane_id']")
    upto 1.6
    h pane split "$shell" --direction down --no-focus >/dev/null
    upto 2.6
    # The app shows a tab made in the space in view by itself.
    h tab create --workspace w5 --cwd "$R/notes" --label Ideas --no-focus >/dev/null
    upto 3.8
    tap w1
    upto 6.6
    wrap
}
layout_camera="0:1:.5:.5 0.4:1:.5:.5 1.2:1.22:.62:.55 2.4:1.22:.62:.55 3.1:1.35:.55:.12 3.7:1.35:.55:.12 \
4.4:1.3:.22:.38 5.6:1.3:.22:.38 6.5:1:.5:.5"

# Claude Code's turn in Chat as it happens: its words and tools come in, the Git card beside it has the diff.
agents() {
    local c old prompt
    ln -sf "$REPO/scripts/welcome-clips/claude.py" "$W/bin/claude"
    old=$(h pane list | json "[p['tab_id'] for p in d['result']['panes'] if p['pane_id'] == '$c2'][0]")
    # A new tab right after the first, in view in the tab bar, in place of the scene's Dark mode tab.
    c=$(o "$c1" "$R/shortlink" agent claude --tab --json | json "d['pane']")
    o "$c" "$R/shortlink" open git . uncommitted --beside "$c" >/dev/null
    h tab close "$old" >/dev/null
    h pane rename "$c" "Dark mode" >/dev/null
    h pane wait-output "$c" --match stand-in --timeout 30000 >/dev/null
    tap "$(h pane list | json "[p['tab_id'] for p in d['result']['panes'] if p['pane_id'] == '$c'][0]")"
    prompt=$(json "list(d['claude'])[1]" <"$W/turns.json")
    sleep 1
    roll "agents-$1"
    upto 0.3
    h pane send-text "$c" "$prompt" >/dev/null
    h pane send-keys "$c" Enter >/dev/null
    upto 6.6
    wrap
}
agents_camera="0:1:.5:.5 0.6:1:.5:.5 1.6:1.3:.45:.55 4.6:1.3:.45:.55 5.6:1.3:.2:.45 6.5:1:.5:.5"

# From a shell: Git, then the browser on the dev server, typed; then a plugin of the user's own, Deploys.
plugins() {
    local shell git
    ln -sf "$R/.cache/ovvi/bin/ovvi" "$W/bin/ovvi"
    shell=$(panes w2:t2 | head -1)
    # As an agent makes one: New Plugin… from the template (built and confirmed), then its own page.
    o "$shell" "$R/api" --timeout 120 plugins new Deploys >/dev/null
    cp "$REPO/scripts/welcome-clips/deploys/package.json" "$W/config/plugins/deploys/"
    cp "$REPO/scripts/welcome-clips/deploys/main."{ts,css} "$W/config/plugins/deploys/src/"
    o "$shell" "$R/api" --timeout 120 plugins reload deploys >/dev/null
    h pane run "$shell" "clear" >/dev/null
    tap w2
    tap w2:t2
    sleep 1
    roll "plugins-$1"
    upto 0.4
    h pane send-text "$shell" "ovvi open git ." >/dev/null
    upto 0.9
    h pane send-keys "$shell" Enter >/dev/null
    upto 2.2
    h pane send-text "$shell" "ovvi open browser localhost:$port --down" >/dev/null
    upto 2.7
    h pane send-keys "$shell" Enter >/dev/null
    upto 4.1
    git=$(h pane list | json "[p['pane_id'] for p in d['result']['panes'] if p['tab_id'] == 'w2:t2' \
and p.get('label', '').startswith('ovvi:git')][0]")
    o "$shell" "$R/api" open deploys --beside "$git" --down >/dev/null
    upto 6.6
    wrap
}
plugins_camera="0:1:.5:.5 0.9:1:.5:.5 1.8:1.22:.72:.45 2.8:1.22:.72:.45 3.6:1.22:.45:.72 4.3:1.22:.45:.72 \
5:1.22:.78:.72 5.8:1.22:.78:.72 6.5:1:.5:.5"

# The machine menu: This Mac and the machines added.
machines() {
    tap w1
    tap w1:t1
    sleep 1
    roll "machines-$1"
    upto 0.8
    tap titlebar.machine
    upto 4.8
    tap titlebar.machine
    upto 6
    wrap
}
machines_camera="0:1:.5:.5 1:1:.5:.5 2:1.35:.25:.32 4.8:1.35:.25:.32 5.8:1:.5:.5"

# The film's crop, in window points: the whole window inside its rounded corners, 2:1.
CROP="6 6 1268 634"

# Crops the film at its 2x, covers the capture mark macOS draws over the window's buttons while it films (with the
# title row's own color), moves the camera over it into 1824 x 912 pixels (2x of the picture's 912 x 456 points),
# HEVC at a low bitrate; its last half second fades back to its first frame, so the loop has no seam.
encode() {
    local film="$C/$1-$2.mp4" length x y w hh wx wy lights keys
    read -r x y w hh <<<"$CROP"
    read -r wx wy _ <"$C/$1-$2.at"
    x=$((x + wx)) y=$((y + wy)) keys=${1}_camera
    length=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$film")
    lights=$(ffmpeg -loglevel error -ss 0.5 -i "$film" -frames:v 1 -vf \
        "crop=2:2:$(((wx + 60) * 2)):$(((wy + 44) * 2)),scale=1:1" -f rawvideo -pix_fmt rgb24 - | xxd -p)
    mkdir -p "$CLIPS"
    # shellcheck disable=SC2086 # the keys are words
    ffmpeg -loglevel error -y -i "$film" -filter_complex "[0:v]fps=60,\
drawbox=$(((wx + 6) * 2)):$(((wy + 4) * 2)):180:76:0x$lights:t=fill,crop=$((w * 2)):$((hh * 2)):$((x * 2)):$((y * 2)),\
scale=iw*2:ih*2:flags=lanczos,$(python3 scripts/welcome-clips/camera.py 1824x912 ${!keys}),format=yuv420p,\
split[a][b];[b]trim=end_frame=1,loop=loop=60:size=1,setpts=N/60/TB,fps=60[s];\
[a][s]xfade=transition=fade:duration=0.5:offset=$(python3 -c "print(round($length - 0.6, 2))")[v]" -map "[v]" \
        -c:v libx265 -tag:v hvc1 -crf 30 -preset slow -x265-params log-level=error -an -movflags +faststart \
        -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
        "$CLIPS/welcome-$1-$2.mp4"
    ls -l "$CLIPS/welcome-$1-$2.mp4"
}

film() {
    local looks=${1:-both} pages=${*:2}
    [ "$looks" = both ] && looks="dark light"
    grep -qs $WORLD /tmp/ovvi-gui.lock/owner || { echo "hold the GUI lock first" >&2 && exit 1; }
    mkdir -p "$C"
    [ -x "$C/film" ] || swiftc "$REPO/scripts/welcome-clips/film.swift" -o "$C/film" 2>/dev/null
    for look in $looks; do
        scene up "$S" "$look" "$SIZE"
        trap 'scene down "$S"' EXIT
        # shellcheck disable=SC1091 # made by `up`: S R pid wid port and the agents' panes
        source "$W/scene.env"
        for page in ${pages:-$PAGES}; do
            "$page" "$look"
        done
        scene down "$S"
        trap - EXIT
    done
}

"$@"
