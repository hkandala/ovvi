#!/usr/bin/env bash
# Usage: scripts/e2e.sh <command>...
set -euo pipefail
cd "$(dirname "$0")/.."
# Inside a herdr pane these point at the user's own session.
unset "${!HERDR_@}"

id=$(openssl rand -hex 3)
one=ovvi-e2e-$id-a
two=ovvi-e2e-$id-b
three=ovvi-e2e-$id-c
four=ovvi-e2e-$id-d
five=ovvi-e2e-$id-e
six=ovvi-e2e-$id-f
seven=ovvi-e2e-$id-g
eight=ovvi-e2e-$id-h
# A session joins the cleanup only once it is up: a failed `up` must not remove a session it did not make. The tests
# make four, six and eight.
made=("$four" "$six" "$eight")
# The app keeps a state folder and a server log per session.
trap 'for s in "${made[@]}"; do scripts/herdr-session.sh down "$s" || true
        rm -rf "$HOME/.local/state/ovvi/$s" "$HOME/Library/Logs/Ovvi/$s.log"; done
    rm -rf /tmp/ovvi-e2e-no-herdr-*' EXIT
for s in "$one" "$two" "$three" "$five" "$seven"; do
    scripts/herdr-session.sh up "$s"
    made+=("$s")
done
herdr session stop "$three" >/dev/null

# The welcome opens on a first launch only; tests run without it (theirs pass -welcomeDone NO).
defaults write dev.ovvi.app.debug welcomeDone -bool YES
rm -rf /tmp/ovvi-e2e-no-config

# The sandboxed test runner cannot reach herdr's sockets.
python3 scripts/e2e-helper.py "$one" "$two" "$three" "$four" "$five" "$six" "$seven" "$eight" -- "$@"
