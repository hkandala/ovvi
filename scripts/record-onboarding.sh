#!/usr/bin/env bash
# Records the welcome's clips and its films in one go, for a quiet Mac: builds the Release app, brings up the welcome
# pictures' scene (scripts/welcome-scene.sh: a herdr world of its own, its own config and home, never the user's
# sessions), films each page's change in the whole main window (2x, 60 fps, the window's rect only, over a plain
# black or white backdrop: scripts/onboarding/film.swift) in dark and light, encodes the clips into
# Ovvi/Onboarding/Clips, then films the whole welcome (testWelcomeFilm: the panel only, dark and light) and writes
# everything to ~/Downloads/ovvi-research/onboarding-v4/.
# Usage: scripts/record-onboarding.sh [clips|encode|films|all] [dark|light|both]   (default: all both)
# Takes the GUI lock (or runs under the user's own hold); Ctrl-C stops it and cleans up what it started.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD WORLD=onboarding S=workbench SIZE=1200x800
W=/tmp/$WORLD C=/tmp/$WORLD-clips CLIPS=$REPO/Ovvi/Onboarding/Clips OUT=$HOME/Downloads/ovvi-research/onboarding-v4
export DERIVED_DATA=${DERIVED_DATA:-/tmp/ovvi-dd-$WORLD}
export OVVI_APP=$DERIVED_DATA/Build/Products/Release/Ovvi.app
STEPS=${1:-all} LOOKS=${2:-both} PAGES=${PAGES:-running layout agents plugins machines}
[ "$LOOKS" = both ] && LOOKS="dark light"
unset "${!HERDR_@}"
HERDR=$(command -v herdr) CLAUDE=$(command -v claude || true)
started=$SECONDS lock= REC= up= BACKDROP= FILM=
say() { printf '\n[%s +%dm%02ds] %s\n' "$(date +%H:%M:%S)" $(((SECONDS - started) / 60)) $(((SECONDS - started) % 60)) "$*"; }

cleanup() {
    if [ -n "$REC" ] && ps -p "$REC" -o command= | grep -qF "$C/film"; then kill "$REC" 2>/dev/null || true; fi
    if [ -n "$BACKDROP" ] && ps -p "$BACKDROP" -o command= | grep -qF "$C/backdrop"; then kill "$BACKDROP" || true; fi
    # A take that did not end well keeps no film: it was not checked.
    [ -n "$FILM" ] && rm -f "$FILM"
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
# Where an element (a space w2, a tab w1:t3, else an accessibility id or title:<a menu item>) shows in the window, as
# "x y": a kept page's copy of it can sit outside the window, where the scene's `click` refuses.
spot() {
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
    echo "$point"
}
# Clicks a spot. On camera, clicks go to spots found before the film: a walk of the accessibility tree holds the app's
# main thread, and its frames stall while it runs (the space switch's fade came out in three steps).
press() {
    # shellcheck disable=SC2086 # x y
    OVVI_APP_PID=$pid "$W/tools/click" $1
}
tap() {
    local point
    point=$(spot "$1") || return 1
    "$W/tools/ax" "$pid" front
    press "$point"
}

# Films the app's windows into $C/<page>-<look>.mp4 until `wrap`.
roll() {
    # The window is key from the first frame, in front of every other app's.
    "$W/tools/ax" "$pid" front
    "$W/tools/ax" "$pid" park 2>/dev/null || true
    # The glass shows what is under the window: black in dark, white in light, as on a plain desktop; right under the
    # window, and only while the film runs.
    # shellcheck disable=SC2046 # x y w h
    BACKDROP_MAX_SECONDS=200 "$C/backdrop" "$([ "$look" = dark ] && echo black || echo white)" $(window) \
        >"$C/backdrop.log" &
    BACKDROP=$!
    for _ in $(seq 600); do grep -q shown "$C/backdrop.log" && break; sleep 0.05; done
    sleep 0.3
    grep -q shown "$C/backdrop.log" || { echo "no backdrop" && exit 1; }
    # The film holds the window's rect alone (film.swift).
    window | awk '{ print 0, 0, $4, $5 }' >"$C/$1.at"
    rm -f "$C/cue"
    mkfifo "$C/cue"
    FILM=$C/$1.mp4
    FILM_MAX_SECONDS=150 "$C/film" "$pid" "$FILM" "$BACKDROP" <"$C/cue" >"$C/film.log" 2>&1 &
    REC=$!
    exec 3>"$C/cue"
    # "recording" comes with the film's first frame: the steps' times are the clip's.
    for _ in $(seq 400); do grep -q recording "$C/film.log" && break; sleep 0.05; done
    grep -q recording "$C/film.log" || { echo "the film did not start: $(cat "$C/film.log")" && exit 1; }
    T0=$(python3 -c "import time; print(time.time())")
}
wrap() {
    exec 3>&-
    wait "$REC"
    REC=
    kill "$BACKDROP"
    BACKDROP=
    # Another app's window came over or under the window while it filmed: the film goes at once (cleanup deletes it).
    grep intruder "$C/film.log" && exit 1
    FILM=
}
# Waits until $1 seconds after the film started: the steps keep their times however long each one takes.
upto() { sleep "$(python3 -c "import time; print(max(0, $T0 + $1 - time.time()))")"; }
# Seconds since the film started.
now() { python3 -c "import time; print(round(time.time() - $T0, 2))"; }

# Each page: what it shows first, then the film of what changes in the whole window.

# The work runs on: the dev server's log takes requests and a build compiles beside it (scripts/onboarding/cargo.py,
# a real build's lines replayed), agents work in the sidebar.
running() {
    local build
    cp "$REPO/scripts/onboarding/cargo.py" "$W/bin/cargo"
    chmod +x "$W/bin/cargo"
    tap w1:t3
    build=$(panes w1:t3 | tail -1)
    # A few columns more for the build, so its longest lines fit (the log's are short).
    h pane resize --pane "$build" --direction left --amount 0.04 >/dev/null
    h pane run "$build" "clear" >/dev/null
    sleep 1
    roll "running-$1"
    (for path in / /style.css /app.js /api/links /api/links /k3vZ9a / /api/links /app.js /api/links; do
        curl -s -o /dev/null "http://localhost:$port$path" || true
        sleep 0.45
    done) 3>&- &
    upto 1
    h pane run "$build" "cargo build --release" >/dev/null
    upto 7.5
    wrap
}

# One pane grows, at an easy pace: a split (the card's own Split Right), a tab, then a space no other clip shows.
layout() {
    local explorer split docs
    tap w5
    explorer=$(panes w5:t1 | head -1)
    sleep 1
    split=$(spot "pane.$explorer.split-right")
    docs=$(spot w3)
    # The docs space once, off camera, so its cards are drawn when the switch shows them.
    press "$docs"
    sleep 3
    tap w5
    sleep 1
    roll "layout-$1"
    # The card's own Split Right, as a click makes it: the new pane asks what it runs.
    upto 1.5
    press "$split"
    upto 3.2
    # The app shows a tab made in the space in view by itself.
    h tab create --workspace w5 --cwd "$R/notes" --label Ideas --no-focus >/dev/null
    upto 5.5
    press "$docs"
    # The switched space stays a while before the loop.
    upto 9.5
    wrap
}

# The real Claude Code for the agents' and plugins' clips, in the scene's home (its own ~/.claude there, never the
# user's), signed in only with what this environment gives (the ANTHROPIC_* variables of an agent's session); asks
# nothing on camera: the folder is trusted, its first launch's notes are seen once off camera, and its settings allow
# the edits and commands the turns make.
real_claude() {
    local p
    [ -x "$W/bin/claude" ] && [ -f "$R/.claude/settings.json" ] && return 0
    (
        umask 077
        # The scene's model, as its other agents show it.
        {
            printf '#!/bin/sh\nexport ANTHROPIC_MODEL=claude-opus-4-5\n'
            printf 'export ANTHROPIC_API_KEY=%q ANTHROPIC_BASE_URL=%q ANTHROPIC_CUSTOM_HEADERS=%q\nexec %q "$@"\n' \
                "${ANTHROPIC_API_KEY:-}" "${ANTHROPIC_BASE_URL:-}" "${ANTHROPIC_CUSTOM_HEADERS:-}" "$CLAUDE"
        } >"$W/bin/claude"
    )
    chmod 700 "$W/bin/claude"
    ln -sf "$R/.cache/ovvi/bin/ovvi" "$W/bin/ovvi"
    python3 - "$R" "$1" <<'PY'
import json, os, sys
home, look = sys.argv[1:]
os.makedirs(f"{home}/.claude", exist_ok=True)
json.dump({"hasCompletedOnboarding": True, "theme": look,
           "projects": {f"{home}/shortlink": {"hasTrustDialogAccepted": True, "hasCompletedProjectOnboarding": True}}},
          open(f"{home}/.claude.json", "w"))
# Every tool call approved, as --dangerously-skip-permissions does, but by a hook: that flag puts "bypass permissions
# on" under the prompt. No permission question can stop a turn.
allow = '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}'
json.dump({"hooks": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": f"echo '{allow}'"}]}]}},
          open(f"{home}/.claude/settings.json", "w"))
PY
    # Ovvi's own skill, as the user's agents have it: Claude Code learns `ovvi open` from it, not from the prompt.
    rm -rf "$R/.claude/skills/ovvi"
    mkdir -p "$R/.claude/skills"
    cp -R "$REPO/skills/ovvi" "$R/.claude/skills/ovvi"
    p=$(h tab create --workspace w4 --cwd "$R/shortlink" --no-focus | json "d['result']['root_pane']['pane_id']")
    h pane run "$p" "claude" >/dev/null
    h pane wait-output "$p" --match "Claude Code v" --timeout 90000 >/dev/null
    sleep 3
    h pane send-text "$p" "/exit" >/dev/null
    h pane send-keys "$p" Enter >/dev/null
    sleep 2
    h tab close "$(tab_of "$p")" >/dev/null
}

# Whether Claude Code (pane $1) has ended its turn: done until the card is seen, then idle.
finished() {
    case $(h pane get "$1" | json "d['result']['pane'].get('agent_status')") in
    idle | done) return 0 ;;
    *) return 1 ;;
    esac
}

# Sends Claude Code (pane $1) a prompt, then waits until its turn has ended.
ask() {
    h pane send-text "$1" "$2" >/dev/null
    h pane send-keys "$1" Enter >/dev/null
    sleep 5
    for _ in $(seq 180); do finished "$1" && return 0; sleep 1; done
    echo "Claude Code's turn did not end" && exit 1
}

# Claude Code in a new tab of shortlink, after the first one (in view in the tab bar), named $1; its first turn,
# off camera, pushes its header (this Mac's model and route) out of view. Prints its pane.
claude_tab() {
    local c
    c=$(o "$c1" "$R/shortlink" agent claude --tab --json | json "d['pane']")
    h pane rename "$c" "$1" >/dev/null
    h pane wait-output "$c" --match "Claude Code v" --timeout 90000 >/dev/null
    # Its card takes the view once Claude Code's hooks have reported it, a few seconds after it draws.
    for _ in $(seq 60); do o "$c" "$R/shortlink" view "$c" tui >/dev/null 2>&1 && break; sleep 1; done
    sleep 2
    # ⌃L: Claude Code draws its screen again, without the launch's lines above it.
    h pane send-keys "$c" ctrl+l >/dev/null
    sleep 1
    ask "$c" "Read server.js and lib/links.js and tell me in a few short bullets what each one does." >&2
    echo "$c"
}

# No header on camera: the turns pushed it out of view.
headerless() {
    h pane read "$1" --source visible | grep -q "Claude Code v" && { echo "Claude Code's header is in view" && exit 1; }
    return 0
}

# Claude Code's finished turn in its terminal (TUI), then a click on Chat: the same turn, as messages, beside Git's
# diff. Nothing else moves, so the clip is two pictures from the film, the TUI and the chat, faded into each other.
agents() {
    local c chat
    real_claude "$1"
    # In place of the scene's Dark mode tab.
    h tab close "$(tab_of "$c2")" >/dev/null
    c=$(claude_tab "Created dates")
    tap w1
    tap "$(tab_of "$c")"
    o "$c" "$R/shortlink" open git . uncommitted --beside "$c" --new >/dev/null
    echo "  the turn, off camera"
    ask "$c" "In public/app.js, show under each link's URL when it was created, like \"Created 3 days ago\". \
Keep the change small, then run npm test and sum it up in two lines."
    headerless "$c"
    # The chat once off camera, so its history is drawn when the click shows it.
    o "$c" "$R/shortlink" view "$c" chat >/dev/null
    sleep 2
    o "$c" "$R/shortlink" view "$c" tui >/dev/null
    sleep 2
    chat=$(spot "pane.$c.view.chat")
    roll "agents-$1"
    upto 1.5
    press "$chat"
    upto 4
    wrap
    o "$c" "$R/shortlink" view "$c" tui >/dev/null
    pictures "$C/agents-$1.mp4" 1 3.5
}

# Turns film $1 into its frames at $2 and $3 s, each held 3.5 s and faded into the next (encode fades the last back
# into the first). The frames stay as the film has them: no trip through RGB.
pictures() {
    local film=$1
    ffmpeg -loglevel error -y -ss "$2" -i "$film" -ss "$3" -i "$film" -filter_complex "\
[0:v]trim=end_frame=1,loop=loop=239:size=1,setpts=N/60/TB,fps=60[a];\
[1:v]trim=end_frame=1,loop=loop=245:size=1,setpts=N/60/TB,fps=60[b];\
[a][b]xfade=transition=fade:duration=0.5:offset=3.5" \
        -c:v libx264 -crf 8 -preset slow -pix_fmt yuv420p "${film%.mp4}-pictures.mp4" || exit 1
    mv "${film%.mp4}-pictures.mp4" "$film"
}

# Claude Code ends its work by opening Git and the deploys plugin beside it, and the browser in a new tab: the film
# runs through its turn, and `reply` keeps the cards opening and Claude Code's whole reply.
plugins() {
    local c opened=0 first= last= count base
    real_claude "$1"
    # As an agent makes one: New Plugin… from the template (built and confirmed), then its own page.
    o "$c1" "$R/shortlink" --timeout 120 plugins new Deploys >/dev/null
    cp "$REPO/scripts/onboarding/deploys/package.json" "$W/config/plugins/deploys/"
    cp "$REPO/scripts/onboarding/deploys/main."{ts,css} "$W/config/plugins/deploys/src/"
    o "$c1" "$R/shortlink" --timeout 120 plugins reload deploys >/dev/null
    tap w1
    # What to open for review is in Claude Code's memory (~/.claude/CLAUDE.md, read as it starts), how in the skill.
    printf '%s\n' "When you finish a change in a repository, open it for me to review with Ovvi (the ovvi skill), one \
at a time: the repository's Git home (its changes and history) beside you, then the Deploys plugin under that Git \
card (beside its pane, --down), then the site (http://localhost:$port) in a browser in a new tab. Then reply with \
what is open for review, one short line each, and under it what changed, in two or three short bullets." \
        >"$R/.claude/CLAUDE.md"
    c=$(claude_tab "Dark mode")
    tap "$(tab_of "$c")"
    # Its tab alone in the space, so the browser's new tab shows clearly, and no card there for Claude Code to reuse.
    for tab in $(h pane list | json "'\n'.join(sorted({p['tab_id'] for p in d['result']['panes'] \
if p['workspace_id'] == 'w1'} - {'$(tab_of "$c")'}))"); do h tab close "$tab" >/dev/null; done
    # Each card once, off camera: their pages and the browser's site load before the film, so none shows empty in it.
    local warm
    warm=$(o "$c" "$R/shortlink" open git . --beside "$c" --json | json "d['pane']")
    o "$c" "$R/shortlink" open browser "localhost:$port" --beside "$warm" --json >/dev/null
    o "$c" "$R/shortlink" open deploys --beside "$warm" --down >/dev/null
    sleep 4
    for warm in $(panes "$(tab_of "$c")" | grep -vx "$c"); do h pane close "$warm" >/dev/null; done
    sleep 1
    base=$(h pane list | json "len(d['result']['panes'])")
    roll "plugins-$1"
    # The prompt is the work alone, and out of view by the time the first card opens.
    h pane send-text "$c" "Finish the dark mode: the theme button only flips color-scheme, so make [data-theme=dark] \
and [data-theme=light] in public/style.css set the colors too, make the button's icon show the mode in use, and run \
npm test." >/dev/null
    h pane send-keys "$c" Enter >/dev/null
    # Two minutes at most: the film and its backdrop never outlive a turn that stalls.
    local until=$((SECONDS + 120))
    while [ $SECONDS -lt $until ]; do
        count=$(h pane list | json "len(d['result']['panes'])")
        if [ "$count" -gt $((base + opened)) ]; then
            opened=$((count - base)) last=$(now)
            if [ -z "$first" ]; then
                first=$last
                h pane read "$c" --source visible | tr -d ' \n' | grep -q onlyflips \
                    && { echo "the prompt is in view" && exit 1; }
            fi
        fi
        [ "$opened" -ge 3 ] && finished "$c" && break
        h pane read "$c" --source visible | grep -q "Do you want to proceed" && { h pane read "$c" --source visible
            echo "Claude Code asks for a permission" && exit 1; }
        sleep 0.2
    done
    [ "$opened" -ge 3 ] || { echo "Claude Code opened $opened cards" && exit 1; }
    last=$(now)
    headerless "$c"
    # As the user asked: Git's home and Deploys beside Claude Code, the browser in a tab of its own, Claude Code's tab
    # still in view.
    h pane list | json "d['result']['panes']" >"$C/panes.json"
    python3 - "$C/panes.json" "$(tab_of "$c")" "$c" <<'PY' || exit 1
import ast, sys
panes, tab, claude = ast.literal_eval(open(sys.argv[1]).read()), sys.argv[2], sys.argv[3]
here = [p.get("label", "") for p in panes if p["tab_id"] == tab and p["pane_id"] != claude]
git = [label for label in here if label.startswith("ovvi:git") and not label.endswith("uncommitted")]
deploys = [label for label in here if label.startswith("ovvi:deploys")]
browser = [p for p in panes if p.get("label", "").startswith("ovvi:browser") and p["tab_id"] != tab
           and p["workspace_id"] == tab.split(":")[0]]
focused = [p for p in panes if p.get("focused")]
if len(here) != 2 or not git or not deploys or len(browser) != 1 or (focused and focused[0]["tab_id"] != tab):
    sys.exit(f"not the cards asked for: {here}, browser tabs {len(browser)}")
PY
    upto "$(python3 -c "print($last + 8)")"
    wrap
    reply "$C/plugins-$1.mp4" "$(python3 -c "print(max(0, $first - 4))")"
}

# Film $1 from $2 s, a few seconds before the first card: the cards as they open (the Git card from the moment its
# page has drawn, no blank card), until a second after the browser's tab shows, then a fade to Claude Code's whole
# reply, held 4 s (its words stream in slowly). The reply is the window's last change: the turn's end shows in herdr a
# few seconds late.
reply() {
    local film=$1 start=$2 tab settled b0 b1 cut
    tab=$(ffmpeg -ss "$start" -i "$film" -vf "crop=440:70:1060:10,select='gt(scene,0.01)',showinfo" -f null - 2>&1 |
        sed -n 's/.*pts_time:\([0-9.]*\).*/\1/p' | head -1)
    settled=$(ffmpeg -ss "$start" -i "$film" -vf freezedetect=n=0.001:d=1.5 -map 0:v -f null - 2>&1 |
        sed -n 's/.*freeze_start: \([0-9.]*\).*/\1/p' | tail -1)
    [ -n "$tab" ] && [ -n "$settled" ] || { echo "no browser tab or no reply in $film" && exit 1; }
    # Where the Git card's lists go, a single gray while its page loads: from its first such frame to its last.
    read -r b0 b1 < <(ffmpeg -loglevel error -ss "$start" -t "$tab" -i "$film" \
        -vf "fps=60,crop=800:150:1550:250,scale=200:38,format=gray" -f rawvideo - | python3 -c "import sys
d, n = sys.stdin.buffer.read(), 200 * 38
flat = [i / 60 for i in range(len(d) // n) if max(d[i * n:(i + 1) * n]) - min(d[i * n:(i + 1) * n]) < 10]
print(flat[0], flat[-1] + 1 / 60) if flat else print(0, 0)")
    cut="[0:v]setpts=PTS-STARTPTS,fps=60[a]"
    [ "$b0" = 0 ] || cut="[0:v]setpts=PTS-STARTPTS,fps=60,split[x][y];[x]trim=end=$b0[x0];\
[y]trim=start=$b1,setpts=PTS-STARTPTS[y0];[x0][y0]concat=n=2:v=1,fps=60[a]"
    ffmpeg -loglevel error -y -ss "$start" -t "$(python3 -c "print($tab + 1.5)")" -i "$film" \
        -ss "$(python3 -c "print($start + $settled + 0.3)")" -i "$film" -filter_complex "$cut;\
[1:v]trim=end_frame=1,loop=loop=309:size=1,setpts=N/60/TB,fps=60[b];\
[a][b]xfade=transition=fade:duration=0.5:offset=$(python3 -c "print(round($tab + 1 - ($b1 - $b0), 3))")" \
        -c:v libx264 -crf 8 -preset slow -pix_fmt yuv420p "${film%.mp4}-reply.mp4" || exit 1
    mv "${film%.mp4}-reply.mp4" "$film"
}

# The machine menu, then Add Machine: Settings opens on a new machine, and an SSH target is typed in (never added).
machines() {
    local machine add field target=alex@build-box typed= screen
    tap w2
    tap w2:t1
    # The window in the screen's middle, where Settings opens: the film holds only the window's rect.
    read -r -a screen <<<"$("$W/tools/ax" "$pid" screen)"
    "$W/tools/ax" "$pid" window $(((screen[0] - ${SIZE%x*}) / 2)) $(((screen[1] - ${SIZE#*x}) / 2 + 12)) \
        "${SIZE%x*}" "${SIZE#*x}" >/dev/null
    sleep 1
    # The whole way once, off camera, for its spots (and Settings' place, which it keeps): no walk of the
    # accessibility tree while the film runs.
    machine=$(spot titlebar.machine)
    press "$machine"
    sleep 1
    add=$(spot "title:Add Machine…")
    press "$add"
    field=$(spot settings.machine.target)
    "$W/tools/ax" "$pid" close
    sleep 1
    # At an easy pace, the target typed fast, and it stays a while before the loop.
    roll "machines-$1"
    upto 1.5
    press "$machine"
    upto 3.2
    press "$add"
    upto 4.4
    press "$field"
    sleep 0.5
    for ((i = 0; i < ${#target}; i++)); do
        typed+=${target:i:1}
        "$W/tools/ax" "$pid" set "$typed"
        sleep 0.04
    done
    sleep 4
    wrap
    "$W/tools/ax" "$pid" set ""
    "$W/tools/ax" "$pid" close
}

# The whole window at the film's 2x, its buttons from the picture taken before it filmed, at 1920 x 1280 pixels (2x of
# the welcome panel's 960 x 640 points, which the clip fills), 60 fps; its last half second fades back to its first
# frame, so the loop has no seam. HEVC Main 4:2:0 at a quality where no artifact shows at 100%, its colors marked as
# what they are: sRGB's curve. Marked bt709's, AVFoundation plays them lighter (dark 33 shows as 36, 43 as 49).
encode() {
    local film="$C/$1-$2.mp4" length wx wy ww wh under
    read -r wx wy ww wh <"$C/$1-$2.at"
    length=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$film")
    # The capture mark covers the window's buttons: the glass under them, from this film, then only the three
    # buttons themselves from the picture (a soft-edged circle each), so no edge of another moment's glass shows.
    under=$(ffmpeg -loglevel error -ss 0.5 -i "$film" -frames:v 1 -vf \
        "crop=2:2:$(((wx + 60) * 2)):$(((wy + 44) * 2)),scale=1:1" -f rawvideo -pix_fmt rgb24 - | xxd -p)
    mkdir -p "$CLIPS"
    ffmpeg -loglevel error -y -i "$film" -i "$C/buttons-$2.png" -filter_complex "[0:v]fps=60,\
crop=$((ww * 2)):$((wh * 2)):$((wx * 2)):$((wy * 2)),drawbox=12:8:180:76:0x$under:t=fill[w];\
[1:v]crop=200:88:0:0,format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':\
a='255*clip(16.5-min(min(hypot(X-45.5,Y-45.5),hypot(X-91.5,Y-45.5)),hypot(X-137.5,Y-45.5)),0,1)'[b];\
[w][b]overlay=0:0,scale=1920:1280:flags=lanczos,format=yuv420p,split[a][f];\
[f]trim=end_frame=1,loop=loop=60:size=1,setpts=N/60/TB,fps=60[s];\
[a][s]xfade=transition=fade:duration=0.5:offset=$(python3 -c "print(round($length - 0.6, 2))"),format=yuv420p,\
setparams=color_primaries=bt709:color_trc=iec61966-2-1:colorspace=bt709[v]" \
        -map "[v]" -c:v libx265 -tag:v hvc1 -crf "${CRF:-24}" -preset slow -an -movflags +faststart \
        -x265-params log-level=error:colorprim=bt709:transfer=iec61966-2-1:colormatrix=bt709 "$CLIPS/welcome-$1-$2.mp4"
}

clips() {
    mkdir -p "$C"
    swiftc "$REPO/scripts/onboarding/film.swift" -o "$C/film" 2>&1 | grep -E "error:" && exit 1
    swiftc "$REPO/scripts/onboarding/backdrop.swift" -o "$C/backdrop" 2>&1 | grep -E "error:" && exit 1
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
        # Nothing of the take stays on screen.
        ! ps -p "$pid" >/dev/null || { echo "the scene's app is still up" && exit 1; }
    done
}

encode_all() {
    local jobs look page
    say "Encoding the clips"
    for look in $LOOKS; do
        for page in $PAGES; do rm -f "$CLIPS/welcome-$page-$look.mp4"; done
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
    # The test bundle's own record of a failure films the whole screen: it goes at once.
    make e2e DERIVED_DATA="$DERIVED_DATA" ONLY=OvviUITests/OvviUITests/testWelcomeFilm >"$C/films.log" 2>&1 \
        || { rm -rf "$DERIVED_DATA/e2e.xcresult"; grep -E "::error" "$C/films.log" || tail -20 "$C/films.log"; exit 1; }
    rm -rf "$DERIVED_DATA/e2e.xcresult"
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
    for tool in herdr node npm ffmpeg ffprobe swiftc xcodebuild python3 curl claude; do
        command -v "$tool" >/dev/null || { echo "missing: $tool" && exit 1; }
    done
    # Claude Code signs in only with what this environment gives (an agent session's ANTHROPIC_*), never ~/.claude.
    [ -n "${ANTHROPIC_API_KEY:-}${ANTHROPIC_BASE_URL:-}" ] || { echo "no ANTHROPIC_* in the environment for Claude Code" \
        && exit 1; }
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
