#!/usr/bin/env bash
# Records the welcome's clips and its films in one go, for a quiet Mac: builds the Release app, brings up the welcome
# pictures' scene (scripts/welcome-scene.sh: a herdr world of its own, its own config and home, never the user's
# sessions), films each page's change in the whole main window (2x, 60 fps, only the app's windows) in dark and
# light, encodes the clips into Ovvi/Onboarding/Clips, then films the whole welcome (testWelcomeFilm: the panel only,
# dark and light) and writes everything to ~/Downloads/ovvi-research/onboarding-v4/.
# Usage: scripts/record-onboarding.sh [clips|encode|films|all] [dark|light|both]   (default: all both)
# Takes the GUI lock (or runs under the user's own hold); Ctrl-C stops it and cleans up what it started.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD WORLD=onboarding S=workbench SIZE=1280x640
W=/tmp/$WORLD C=/tmp/$WORLD-clips CLIPS=$REPO/Ovvi/Onboarding/Clips OUT=$HOME/Downloads/ovvi-research/onboarding-v4
export DERIVED_DATA=${DERIVED_DATA:-/tmp/ovvi-dd-$WORLD}
export OVVI_APP=$DERIVED_DATA/Build/Products/Release/Ovvi.app
STEPS=${1:-all} LOOKS=${2:-both} PAGES="running layout agents plugins machines"
[ "$LOOKS" = both ] && LOOKS="dark light"
unset "${!HERDR_@}"
HERDR=$(command -v herdr)
started=$SECONDS lock= REC= up=
say() { printf '\n[%s +%dm%02ds] %s\n' "$(date +%H:%M:%S)" $(((SECONDS - started) / 60)) $(((SECONDS - started) % 60)) "$*"; }

cleanup() {
    if [ -n "$REC" ] && ps -p "$REC" -o command= | grep -qF "$C/film"; then kill "$REC" 2>/dev/null || true; fi
    if [ -n "$up" ] && [ -d "$W" ]; then scene down "$S" >/dev/null 2>&1 || true; fi
    [ -n "$lock" ] && rm -rf /tmp/ovvi-gui.lock
    return 0
}
trap cleanup EXIT
trap 'say "Stopped."; exit 130' INT TERM

scene() { scripts/welcome-scene.sh "$1" $WORLD "${@:2}"; }
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
tab_of() { h pane list | json "[p['tab_id'] for p in d['result']['panes'] if p['pane_id'] == '$1'][0]"; }
# The window's id and frame, in screen points.
window() { "$W/tools/ax" "$pid" window; }
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

# Films the app's windows into $C/<page>-<look>.mp4 until `wrap`.
roll() {
    "$W/tools/ax" "$pid" park 2>/dev/null || true
    sleep 0.3
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
    REC=
}
# Waits until $1 seconds after the film started: the steps keep their times however long each one takes.
upto() { sleep "$(python3 -c "import time; print(max(0, $T0 + $1 - time.time()))")"; }

# Each page: what it shows first, then the film of what changes in the whole window.

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
    upto 6
    wrap
}

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
    upto 6
    wrap
}

# Claude Code at work in its terminal (TUI), then a click on Chat: the same turn, as messages, beside Git's diff.
agents() {
    local c prompt
    printf '#!/bin/sh\nexec %q %q "$@"\n' "$(command -v python3)" "$REPO/scripts/onboarding/claude.py" >"$W/bin/claude"
    chmod +x "$W/bin/claude"
    # In place of the scene's Dark mode tab: a new one right after the first, in view in the tab bar.
    h tab close "$(tab_of "$c2")" >/dev/null
    c=$(o "$c1" "$R/shortlink" agent claude --tab --json | json "d['pane']")
    h pane rename "$c" "Dark mode" >/dev/null
    h pane wait-output "$c" --match "Welcome to Claude Code" --timeout 30000 >/dev/null
    tap "$(tab_of "$c")"
    sleep 1
    o "$c" "$R/shortlink" open git . uncommitted --beside "$c" >/dev/null
    sleep 2
    o "$c" "$R/shortlink" view "$c" tui >/dev/null
    sleep 1.5
    prompt=$(json "list(d['claude'])[1]" <"$W/turns.json")
    roll "agents-$1"
    upto 0.3
    h pane send-text "$c" "$prompt" >/dev/null
    h pane send-keys "$c" Enter >/dev/null
    upto 3
    tap "pane.$c.view.chat" || o "$c" "$R/shortlink" view "$c" chat >/dev/null
    upto 7
    wrap
}

# From a shell: Git, then the browser on the dev server, typed; then a plugin of the user's own, Deploys.
plugins() {
    local shell git
    ln -sf "$R/.cache/ovvi/bin/ovvi" "$W/bin/ovvi"
    shell=$(panes w2:t2 | head -1)
    # As an agent makes one: New Plugin… from the template (built and confirmed), then its own page.
    o "$shell" "$R/api" --timeout 120 plugins new Deploys >/dev/null
    cp "$REPO/scripts/onboarding/deploys/package.json" "$W/config/plugins/deploys/"
    cp "$REPO/scripts/onboarding/deploys/main."{ts,css} "$W/config/plugins/deploys/src/"
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
    # What ovvi answers is no part of the picture: ⌃L, as one clears a shell.
    upto 1.6
    h pane send-keys "$shell" ctrl+l >/dev/null
    upto 2.2
    h pane send-text "$shell" "ovvi open browser localhost:$port --down" >/dev/null
    upto 2.7
    h pane send-keys "$shell" Enter >/dev/null
    upto 3.4
    h pane send-keys "$shell" ctrl+l >/dev/null
    upto 3.9
    git=$(h pane list | json "[p['pane_id'] for p in d['result']['panes'] if p['tab_id'] == 'w2:t2' \
and p.get('label', '').startswith('ovvi:git')][0]")
    o "$shell" "$R/api" open deploys --beside "$git" --down >/dev/null
    upto 7
    wrap
}

# The machine menu: This Mac and the machines added.
machines() {
    tap w1
    tap w1:t1
    sleep 1
    roll "machines-$1"
    upto 0.8
    tap titlebar.machine
    upto 4.6
    tap titlebar.machine
    upto 5.6
    wrap
}

# The whole window at the film's 2x, its buttons from the picture taken before it filmed, at 1824 x 912 pixels (2x of
# the picture's 912 x 456 points), 60 fps; its last half second fades back to its first frame, so the loop has no
# seam. HEVC Main 4:2:0, bt709, at a quality where no artifact shows at 100%.
encode() {
    local film="$C/$1-$2.mp4" length wx wy ww wh
    read -r wx wy ww wh <"$C/$1-$2.at"
    length=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$film")
    mkdir -p "$CLIPS"
    ffmpeg -loglevel error -y -i "$film" -i "$C/buttons-$2.png" -filter_complex "[0:v]fps=60,\
crop=$((ww * 2)):$((wh * 2)):$((wx * 2)):$((wy * 2))[w];[1:v]crop=200:88:0:0[b];[w][b]overlay=0:0,\
scale=1824:912:flags=lanczos,format=yuv420p,split[a][f];[f]trim=end_frame=1,loop=loop=60:size=1,setpts=N/60/TB,fps=60[s];\
[a][s]xfade=transition=fade:duration=0.5:offset=$(python3 -c "print(round($length - 0.6, 2))"),format=yuv420p[v]" \
        -map "[v]" -c:v libx265 -tag:v hvc1 -crf "${CRF:-24}" -preset slow -an -movflags +faststart \
        -x265-params log-level=error:colorprim=bt709:transfer=bt709:colormatrix=bt709 "$CLIPS/welcome-$1-$2.mp4"
}

clips() {
    mkdir -p "$C"
    swiftc "$REPO/scripts/onboarding/film.swift" -o "$C/film" 2>&1 | grep -E "error:" && exit 1
    for look in $LOOKS; do
        say "The scene, $look (about 45 s)"
        scene up "$S" "$look" "$SIZE" >/dev/null
        up=1
        # shellcheck disable=SC1091 # made by `up`: S R pid wid port and the agents' panes
        source "$W/scene.env"
        # macOS draws its capture mark over the window's buttons while it films: the clips take the buttons from a
        # picture of the window taken now, while nothing films.
        "$W/tools/ax" "$pid" front
        "$W/tools/ax" "$pid" park 2>/dev/null || true
        sleep 2
        screencapture -x -o -l "$wid" "$C/buttons-$look.png"
        for page in $PAGES; do
            say "Clip: $page, $look"
            "$page" "$look"
        done
        scene down "$S" >/dev/null
        up=
    done
}

encode_all() {
    local jobs look page
    say "Encoding the clips"
    for look in $LOOKS; do
        rm -f "$CLIPS"/welcome-*-"$look".mp4
        jobs=()
        for page in $PAGES; do
            encode "$page" "$look" &
            jobs+=($!)
        done
        for job in "${jobs[@]}"; do wait "$job"; done
        for page in $PAGES; do
            [ -s "$CLIPS/welcome-$page-$look.mp4" ] || { echo "no clip $page $look" && exit 1; }
        done
    done
    echo "  the clips in all: $(du -ch "$CLIPS"/*.mp4 | tail -1 | cut -f1)"
}

# The welcome in full (the panel only, on a plain backdrop: never the screen), then trimmed to the panel's first frame
# and checked: the first frame must be the backdrop or the panel, gray at its edges.
films() {
    local look film first
    say "Films: building the tests and filming the welcome, dark then light (about 8 min)"
    mkdir -p "$C"
    make e2e DERIVED_DATA="$DERIVED_DATA" ONLY=OvviUITests/OvviUITests/testWelcomeFilm >"$C/films.log" 2>&1 \
        || { tail -20 "$C/films.log"; exit 1; }
    mkdir -p "$OUT"
    for look in dark light; do
        film=/tmp/ovvi-welcome/$(basename "$REPO")-$look.mp4
        [ -s "$film" ] || { echo "no film $film: is Screen Recording on for this terminal?" && exit 1; }
        first=$(ffmpeg -loglevel error -i "$film" -vf "fps=20,crop=4:4:1022:300,format=gray" -f rawvideo \
            -pix_fmt gray - | python3 -c "import sys; d = sys.stdin.buffer.read()
print(next((i / 20 for i in range(0, len(d) // 16) if max(abs(b - 128) for b in d[i * 16:i * 16 + 16]) > 12), 0))")
        python3 - "$film" <<'EOF' || { echo "the film's first frame is not the backdrop: not used" && exit 1; }
import subprocess, sys
edge = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", sys.argv[1], "-frames:v", "1", "-vf",
                       "crop=iw:4:0:0,format=gray", "-f", "rawvideo", "-"], capture_output=True).stdout
sys.exit(0 if edge and max(abs(b - 128) for b in edge) <= 12 else 1)
EOF
        ffmpeg -loglevel error -y -ss "$(python3 -c "print(max(0, $first - 0.5))")" -i "$film" -vf fps=60 \
            -c:v libx264 -crf 14 -preset slow -pix_fmt yuv420p -movflags +faststart "$OUT/film-$look.mp4"
        rm -f "$film"
    done
}

publish() {
    mkdir -p "$OUT/clips"
    cp "$CLIPS"/welcome-*.mp4 "$OUT/clips/"
    for clip in "$CLIPS"/welcome-*.mp4; do
        ffmpeg -loglevel error -y -ss 3 -i "$clip" -frames:v 1 "$OUT/clips/$(basename "${clip%.mp4}").png"
    done
    local report=$HOME/Downloads/ovvi-research/onboarding-src/v4/report.py
    [ -f "$report" ] && python3 "$report"
    return 0
}

# The tools, and the two permissions the terminal that runs this needs: Screen Recording (the films) and Accessibility
# (the scene's clicks).
preflight() {
    local tool
    for tool in herdr node npm ffmpeg ffprobe swiftc xcodebuild python3 curl; do
        command -v "$tool" >/dev/null || { echo "missing: $tool" && exit 1; }
    done
    mkdir -p "$C"
    printf 'import ApplicationServices\nimport ScreenCaptureKit\nguard AXIsProcessTrusted() else { exit(1) }\n%s\n' \
        'do { _ = try await SCShareableContent.current } catch { exit(2) }' >"$C/allowed.swift"
    swiftc "$C/allowed.swift" -o "$C/allowed" 2>&1 | grep -E "error:" && exit 1
    "$C/allowed" || case $? in
    1) echo "Allow Accessibility for this terminal (System Settings > Privacy & Security), then run it again" && exit 1 ;;
    *) echo "Allow Screen Recording for this terminal (System Settings > Privacy & Security), then run it again" && exit 1 ;;
    esac
}

# The user's own hold (owner "user…"), or one the caller took for this run (LOCKED=1), else this run takes it.
if [ -n "${LOCKED:-}" ]; then
    :
elif [ -d /tmp/ovvi-gui.lock ]; then
    grep -qs '^user' /tmp/ovvi-gui.lock/owner || { echo "the GUI lock is held by $(cat /tmp/ovvi-gui.lock/owner)" \
        && exit 1; }
else
    mkdir /tmp/ovvi-gui.lock && echo "record-onboarding $(date +%H:%M)" >/tmp/ovvi-gui.lock/owner && lock=1
fi
preflight
echo "Recording the welcome: about 25-30 minutes (build 4, clips 8, encoding 4, films 10). Quit Ovvi Dev if it runs."
echo "Don't touch the mouse or the keyboard meanwhile; Ctrl-C stops it and cleans up."
case $STEPS in
clips) clips ;;
encode) encode_all ;;
films) films && publish ;;
all)
    say "Building the Release app (about 4 min)"
    make app DERIVED_DATA="$DERIVED_DATA" >"/tmp/$WORLD-build.log" 2>&1 || { tail -20 "/tmp/$WORLD-build.log"; exit 1; }
    clips
    encode_all
    films
    publish
    rm -rf "$C"
    ;;
*) echo "usage: $0 [clips|encode|films|all] [dark|light|both]" && exit 2 ;;
esac
say "Done. Clips: $CLIPS ($(du -ch "$CLIPS"/*.mp4 | tail -1 | cut -f1)); films and clips: $OUT"
