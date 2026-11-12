#!/usr/bin/env bash
# Usage: scripts/herdr-session.sh up|down <ovvi-e2e-*|ovvi-dev-*>
set -euo pipefail

usage="usage: $0 up|down <ovvi-e2e-*|ovvi-dev-*>"
cmd=${1:?$usage}
name=${2:?$usage}
case $name in
ovvi-e2e-* | ovvi-dev-*) ;;
*) echo "refusing '$name': only ovvi-e2e-* and ovvi-dev-* sessions are throwaway" >&2 && exit 2 ;;
esac
# Inside a herdr pane these point at the user's own session.
unset "${!HERDR_@}"
log="${TMPDIR:-/tmp}/herdr-$name.log"

# Retries a command for up to 60 s: a bound for failures only, as a starved Mac took over 5 s (lessons.md).
retry() {
    local end=$((SECONDS + 60))
    until "$@" >/dev/null 2>&1; do
        ((SECONDS < end)) || return 1
        sleep 0.1
    done
}

exists() {
    local list
    list=$(herdr session list --json) || exit 1
    grep -qF "\"name\":\"$name\"" <<<"$list"
}

case $cmd in
up)
    exists && echo "refusing '$name': it already exists" >&2 && exit 1
    nohup herdr --session "$name" server >"$log" 2>&1 &
    pid=$!
    retry herdr --session "$name" workspace list && exit 0
    kill "$pid" 2>/dev/null || true
    herdr session delete "$name" >/dev/null 2>&1 || true
    echo "herdr session '$name' did not start:" >&2 && cat "$log" >&2 && exit 1
    ;;
down)
    rm -f "$log"
    # The app starts servers as one-shot launchd jobs; launchd keeps them loaded after they stop.
    launchctl bootout "gui/$(id -u)/dev.ovvi.app.herdr.$name" 2>/dev/null || true
    exists || exit 0
    herdr session stop "$name" >/dev/null 2>&1 || true
    retry herdr session delete "$name" && exit 0
    echo "herdr session '$name' did not stop" >&2 && exit 1
    ;;
*) echo "$usage" >&2 && exit 2 ;;
esac
