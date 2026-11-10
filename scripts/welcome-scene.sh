#!/usr/bin/env bash
# The welcome pictures' scene: Ovvi Dev on a herdr session full of plausible work, in a world of its own.
#
#   scripts/welcome-scene.sh up <world> <session> <dark|light> [WxH]  # 35-60 s; prints the app's pid and window id
#   scripts/welcome-scene.sh click <world> <id> [n]  # a space (w2), a tab (w1:t3) or the n-th of an accessibility id
#   scripts/welcome-scene.sh shot <world> <name>     # /tmp/<world>/shots/<name>-<look>.png: the main window at 2x
#   scripts/welcome-scene.sh down <world> <session>  # quits that app; deletes the session, the world and its home
#
# Hold the GUI lock (playbook/workflow.md) from `up` to `down`: the app runs and takes clicks meanwhile. Copy the shots
# out before `down`. Example: `up p57y1 work light`, `shot p57y1 chat`, `click p57y1 w1:t2`, `shot p57y1 git`,
# `click p57y1 titlebar.machine`, `shot p57y1 machines`, `down p57y1 work`. `click` brings the app in front first and
# clicks only into its window; source /tmp/<world>/scene.env for the agents' panes (c1 c2 cx pi), e.g.
# `click p57y1 "pane.$c1.zoom"` to show the chat alone.
#
# The world /tmp/<world>/ holds its own herdr (XDG_CONFIG_HOME), a clean zsh (ZDOTDIR), Ovvi's config folder and
# archived home, and bin/ with the repository's stand-ins as claude, codex and pi, which play scripted turns, and a
# drawn OpenCode (welcome-scene/tui.py). Its home is /Users/Shared/welcome-scene/<world> (/tmp/<world>/home), for
# herdr, the shells and the app: it holds the repositories (welcome-scene/scene.py) and the app shows it as ~ (prompts
# `~/shortlink %`). Ovvi Dev comes from $OVVI_APP, else $DERIVED_DATA (default /tmp/ovvi-dd-<world>). Several worlds
# run at once: each has its own herdr, home and dev server port.
#
# The scene (herdr ids, as `click` takes them):
#   w1 shortlink  t1 Link expiry    Claude Code's finished turn in Chat (its second run of tools open) | Browser on
#                                   the dev server (http://localhost:<port>, a free port from 5173)
#                 t2 Dark mode      Claude Code at work in Chat | Git, the uncommitted diff
#                 t3 Server         the dev server's log | npm test
#                 t4 Review         git log | Git on the last commit
#                 t5 Files          README.md in File Explorer
#   w2 api        t1 Rate limit     Codex, finished, in Chat | Git, the uncommitted diff
#                 t2 Shell          git status and log
#   w3 docs       t1 Domains guide  pi at work in Chat | the guide it writes, in File Explorer
#   w4 linkctl    t1 Release        OpenCode asking a question (needs you) | CHANGELOG.md
#   w5 notes      t1 Roadmap        roadmap.md in File Explorer
# The app opens on w1:t1. Three made-up machines on 192.0.2.x are in the machine menu (titlebar.machine).
set -euo pipefail

usage="usage: $0 up <world> <session> <dark|light> [WxH] | click <world> <id> [n] | shot <world> <name>
       $0 down <world> <session>"
die() { echo "welcome-scene: $*" >&2 && exit 1; }
cmd=${1:-} world=${2:-}
[[ $world =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "$usage"
W=/tmp/$world
# The world's home folder, for herdr, its shells and the app (CFFIXED_USER_HOME), so the app shows the repositories as
# ~/shortlink: not under /tmp, whose /private the app's home drops and herdr's folders keep.
H=/Users/Shared/welcome-scene/$world
kit=$(cd "$(dirname "$0")" && pwd)/welcome-scene
# Inside a herdr pane these point at the user's own session; keep them out of everything here.
unset "${!HERDR_@}"
HERDR=$(command -v herdr) || die "no herdr"
[ "$cmd" = up ] || { [ -f "$W/scene.env" ] || die "no scene in $W"; source "$W/scene.env"; }

# herdr and ovvi in the world's session only: ovvi as pane $1, from folder $2.
h() { env -i HOME="$H" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$W/xdg" "$HERDR" --session "$S" "$@"; }
o() {
    local pane=$1 dir=$2
    shift 2
    (cd "$dir" && env -i HOME="$H" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$W/xdg" HERDR_SESSION="$S" \
        HERDR_BIN_PATH="$HERDR" HERDR_PANE_ID="$pane" sh "$H/.cache/ovvi/bin/ovvi" "$@")
}
# The pane id in herdr's or ovvi's JSON answer.
pane() {
    python3 -c 'import json, sys; d = json.load(sys.stdin); r = d.get("result")
print((r.get("root_pane") or r["pane"])["pane_id"] if r else d["pane"])'
}
listed() { env -u XDG_CONFIG_HOME "$HERDR" session list --json | grep -qF "\"name\":\"$1\""; }

up() {
    S=${1:?$usage} look=${2:?$usage} size=${3:-1440x900}
    [[ $S =~ ^[a-z][a-z0-9-]*$ && $look =~ ^(dark|light)$ && $size =~ ^[0-9]+x[0-9]+$ ]] || die "$usage"
    R=$H APP=${OVVI_APP:-${DERIVED_DATA:-/tmp/ovvi-dd-$world}/Build/Products/Debug/Ovvi Dev.app}
    [ -d "$APP" ] || die "no $APP: build it (make build DERIVED_DATA=…) or set OVVI_APP"
    [ ! -e "$W" ] && [ ! -e "$H" ] || die "$W or $H exists: down it first"
    listed "$S" && die "the user's herdr has a session '$S'"
    started=$SECONDS
    mkdir -p "$W"/{xdg,zdot,config,archived,bin,tmp,tools,shots} "$H"
    touch "$H/.welcome-scene"
    ln -s "$H" "$W/home"
    printf 'S=%q\nR=%q\nlook=%q\nsize=%q\n' "$S" "$R" "$look" "$size" >"$W/scene.env"
    # A failure takes it all down again, the app first.
    trap 'source "$W/scene.env"; down "$S"' EXIT
    # The tools compile while the rest is made (swiftc takes a while on a busy Mac).
    local builds=()
    swiftc -O -o "$W/tools/ax" "$kit/ax.swift" &
    builds+=($!)
    cat "$kit/../posting.swift" "$kit/click.swift" >"$W/tools/click.swift"
    swiftc -O -o "$W/tools/click" "$W/tools/click.swift" &
    builds+=($!)
    swiftc -O -o "$W/tools/crop" "$kit/crop.swift" &
    builds+=($!)
    python3 "$kit/scene.py" "$R" "$W/turns.json"

    local py node path port
    py=$(command -v python3) node=$(dirname "$(command -v node)")
    path="$W/bin:$node:$(dirname "$HERDR"):/usr/bin:/bin:/usr/sbin:/sbin"
    for agent in claude codex pi; do
        printf '#!/bin/sh\nexec %q %q "$@"\n' "$py" "$kit/../$agent-stand-in.py" >"$W/bin/$agent"
    done
    printf '#!/bin/sh\nexec %q %q opencode blocked %q\n' "$py" "$kit/tui.py" "$kit/opencode.txt" >"$W/bin/opencode"
    chmod +x "$W"/bin/*
    # /etc/zprofile's path_helper puts the system's folders first: the stand-ins go first again in .zshrc.
    printf 'export PATH=%q\n' "$path" >"$W/zdot/.zshenv"
    cat >"$W/zdot/.zshrc" <<EOF
export PATH=$(printf %q "$path") CLICOLOR=1
unset HISTFILE
PROMPT='%F{blue}%~%f %# '
EOF
    cp "$W/zdot/.zshenv" "$W/zdot/.zprofile"
    printf '[user]\n\tname = Alex Kim\n\temail = alex@shortlink.dev\n[init]\n\tdefaultBranch = main\n' >"$H/.gitconfig"
    port=$(python3 -c '
import random, socket
for port in random.sample(range(5173, 5300), 127):
    try:
        socket.create_server(("127.0.0.1", port)).close()
        print(port)
        break
    except OSError:
        pass')
    printf 'port=%q\n' "$port" >>"$W/scene.env"

    env -i HOME="$H" USER="$USER" LOGNAME="$USER" SHELL=/bin/zsh LANG=en_US.UTF-8 TMPDIR="$W/tmp/" PATH="$path" \
        ZDOTDIR="$W/zdot" XDG_CONFIG_HOME="$W/xdg" PORT="$port" \
        OVVI_STAND_IN_SCENE="$W/turns.json" nohup "$HERDR" --session "$S" server >"$W/herdr.log" 2>&1 &
    for _ in $(seq 50); do h workspace list >/dev/null 2>&1 && break; sleep 0.2; done
    h workspace list >/dev/null || die "herdr did not start: $(cat "$W/herdr.log")"
    listed "$S" && die "'$S' leaked into the user's herdr"

    # The spaces and tabs, and the terminals that need no app.
    local w1 w2 w3 w4 w5 p
    w1=$(h workspace create --cwd "$R/shortlink" --label shortlink --no-focus | pane)
    w2=$(h workspace create --cwd "$R/api" --label api --no-focus | pane)
    w3=$(h workspace create --cwd "$R/docs" --label docs --no-focus | pane)
    w4=$(h workspace create --cwd "$R/linkctl" --label linkctl --no-focus | pane)
    w5=$(h workspace create --cwd "$R/notes" --label notes --no-focus | pane)
    h tab rename w1:t1 "Link expiry" >/dev/null
    h tab rename w2:t1 "Rate limit" >/dev/null
    h tab rename w3:t1 "Domains guide" >/dev/null
    h tab rename w4:t1 "Release" >/dev/null
    h tab rename w5:t1 "Roadmap" >/dev/null
    local t2 t3 t4 t5 a2
    t2=$(h tab create --workspace w1 --cwd "$R/shortlink" --label "Dark mode" --no-focus | pane)
    t3=$(h tab create --workspace w1 --cwd "$R/shortlink" --label Server --no-focus | pane)
    t4=$(h tab create --workspace w1 --cwd "$R/shortlink" --label Review --no-focus | pane)
    t5=$(h tab create --workspace w1 --cwd "$R/shortlink" --label Files --no-focus | pane)
    a2=$(h tab create --workspace w2 --cwd "$R/api" --label Shell --no-focus | pane)
    sleep 1
    h pane run "$t3" "clear; npm run dev" >/dev/null
    p=$(h pane split "$t3" --direction right --cwd "$R/shortlink" | pane)
    h pane run "$p" "clear; npm test" >/dev/null
    h pane run "$t4" "clear; git log --oneline --graph --decorate" >/dev/null
    h pane run "$a2" "clear; git status --short; echo; git log --oneline --decorate" >/dev/null
    h pane run "$w4" "clear; opencode" >/dev/null

    # The plugins install from the user's npm cache, as they would with the real home.
    open -n "$APP" --env HOME="$H" --env CFFIXED_USER_HOME="$H" --env XDG_CONFIG_HOME="$W/xdg" --env ZDOTDIR="$W/zdot" \
        --env npm_config_cache="$HOME/.npm" --env npm_config_prefer_offline=true \
        --args -session "$S" -configFolder "$W/config" -archivedHome "$W/archived" -welcomeDone YES \
        -appearance "$look" -interfaceStyle glass -machines "$(cat "$kit/machines.json")" \
        -ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO -notifyNeedsYou NO -notifyFinished NO \
        -notifyFromAgents NO -terminalFont "" -cursorStyle block -cursorBlink NO
    local pid=
    for _ in $(seq 100); do
        for candidate in $(pgrep -f "Ovvi Dev.app/Contents/MacOS/Ovvi -session $S " || true); do
            ps -p "$candidate" -o command= | grep -qF -- "$W/config" && pid=$candidate
        done
        [ -n "$pid" ] && break
        sleep 0.2
    done
    [ -n "$pid" ] || die "Ovvi Dev did not start"
    printf 'pid=%q\n' "$pid" >>"$W/scene.env"
    wait "${builds[@]}"
    local wid=
    for _ in $(seq 100); do
        wid=$("$W/tools/ax" "$pid" window 2>/dev/null | cut -d' ' -f1) && [ -n "$wid" ] && break
        sleep 0.2
    done
    [ -n "$wid" ] || die "no window"
    "$W/tools/ax" "$pid" window 40 60 "${size%x*}" "${size#*x}" >/dev/null
    "$W/tools/ax" "$pid" front
    printf 'wid=%q\n' "$wid" >>"$W/scene.env"
    for _ in $(seq 60); do o "$w1" "$R/shortlink" info --json >/dev/null 2>&1 && break; sleep 1; done

    # The plugins and the agents, through Ovvi; then each agent's prompt once it is up.
    local c1 c2 cx pi g
    c1=$(o "$w1" "$R/shortlink" agent claude --json | pane)
    o "$w1" "$R/shortlink" open browser "http://localhost:$port/" --beside "$c1" >/dev/null
    c2=$(o "$t2" "$R/shortlink" agent claude --json | pane)
    o "$t2" "$R/shortlink" open git . uncommitted --beside "$c2" >/dev/null
    o "$t4" "$R/shortlink" open git . "$(git -C "$R/shortlink" rev-parse --short HEAD)" --beside "$t4" >/dev/null
    o "$t5" "$R/shortlink" open ./README.md --beside "$t5" >/dev/null
    cx=$(o "$w2" "$R/api" agent codex --json | pane)
    o "$w2" "$R/api" open git . uncommitted --beside "$cx" >/dev/null
    pi=$(o "$w3" "$R/docs" agent pi --json | pane)
    o "$w3" "$R/docs" open ./guide/custom-domains.md --beside "$pi" >/dev/null
    o "$w4" "$R/linkctl" open ./CHANGELOG.md --beside "$w4" >/dev/null
    o "$w5" "$R/notes" open ./roadmap.md --beside "$w5" >/dev/null
    for p in "$w1" "$t2" "$t5" "$w2" "$w3" "$w5"; do h pane close "$p" >/dev/null; done
    # As the agents name their sessions.
    h pane rename "$c1" "Link expiry" >/dev/null
    h pane rename "$c2" "Dark mode" >/dev/null
    h pane rename "$cx" "Rate limit" >/dev/null
    h pane rename "$pi" "Custom domains guide" >/dev/null
    h pane rename "$w4" "Publish 0.3.0" >/dev/null
    printf 'c1=%q\nc2=%q\ncx=%q\npi=%q\n' "$c1" "$c2" "$cx" "$pi" >>"$W/scene.env"
    for p in "$c1" "$c2" "$cx" "$pi"; do
        h pane wait-output "$p" --match "stand-in" --timeout 30000 >/dev/null
    done
    python3 - "$W/turns.json" "$c1" "$c2" "$cx" "$pi" <<'EOF' | while IFS=$'\t' read -r p text; do
import json, sys
turns, panes = json.load(open(sys.argv[1])), sys.argv[2:]
for pane, (agent, index) in zip(panes, [("claude", 0), ("claude", 1), ("codex", 0), ("pi", 0)]):
    print(pane, list(turns[agent])[index], sep="\t")
EOF
        h pane send-text "$p" "$text" >/dev/null
        h pane send-keys "$p" Enter >/dev/null
    done
    sleep 3
    # The finished turn's second run of tools, open.
    click 'chat.'"$c1"'.stack' 2
    sleep 1
    trap - EXIT
    echo "pid $pid window $wid port $port in $((SECONDS - started)) s"
}

# Clicks the centre of an element: a space (w2), a tab (w1:t3), else an accessibility id; the n-th one of that id.
click() {
    local id=${1:?$usage} n=${2:-1} frame
    [[ $id =~ ^w[0-9]+$ ]] && id=workspace.$id
    [[ $id =~ ^w[0-9]+:t[0-9]+$ ]] && id=tab.$id
    # Up to 30 s: on a busy Mac the app may not have drawn it yet.
    for _ in $(seq 60); do
        frame=$("$W/tools/ax" "$pid" find "$id" | sed -n "${n}p")
        [ -n "$frame" ] && break
        sleep 0.5
    done
    [ -n "$frame" ] || die "no $id in the window"
    read -r _ x y width height _ <<<"$frame"
    "$W/tools/ax" "$pid" front
    OVVI_APP_PID=$pid "$W/tools/click" $((x + width / 2)) $((y + height / 2))
}

shot() {
    local name=${1:?$usage}
    local file=$W/shots/$name-$look.png
    "$W/tools/ax" "$pid" park
    sleep 0.3
    screencapture -x -o -l "$wid" "$file"
    "$W/tools/crop" "$file" $((${size#*x} * 2))
    echo "$file"
}

down() {
    [ "${1:-}" = "$S" ] || die "$W holds session '$S', not '${1:-}'"
    if [ -n "${pid:-}" ] && ps -p "$pid" -o command= | grep -qF -- "$W/config"; then
        kill "$pid"
        for _ in $(seq 50); do ps -p "$pid" >/dev/null || break; sleep 0.2; done
    fi
    h session stop "$S" >/dev/null 2>&1 || true
    env -i HOME="$HOME" PATH=/usr/bin:/bin XDG_CONFIG_HOME="$W/xdg" "$HERDR" session delete "$S" >/dev/null 2>&1 || true
    # A server the app started itself (D47) is a launchd job by the session's name: only if it is this world's.
    local job=gui/$(id -u)/dev.ovvi.app.herdr.$S
    launchctl print "$job" 2>/dev/null | grep -qF "$W/" && launchctl bootout "$job" 2>/dev/null || true
    rm -rf "$HOME/.local/state/ovvi/$S"
    [ -f "$H/.welcome-scene" ] && rm -rf "$H"
    rmdir "$(dirname "$H")" 2>/dev/null || true
    rm -rf "$W"
}

case $cmd in
up | click | shot | down) "$cmd" "${@:3}" ;;
*) die "$usage" ;;
esac
