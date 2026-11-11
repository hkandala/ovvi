#!/bin/sh
# Deletes all of one Ovvi build's local data on this Mac, so it starts as on a fresh install.
# Usage: scripts/reset-app-data.sh [--dry-run] [bundle id]   (default dev.ovvi.app, the installed app)
# Never touches herdr's sessions or their servers, nor ~/.pi, ~/.claude, ~/.codex or any agent's files.
set -eu

dry=
[ "${1:-}" = --dry-run ] && { dry=1; shift; }
id=${1:-dev.ovvi.app}
case $id in
dev.ovvi.app | dev.ovvi.app.*) ;;
*) echo "not an Ovvi bundle id: $id" >&2; exit 2 ;;
esac
if lsappinfo find bundleid="$id" | grep -q .; then
    echo "$id is running: quit it first" >&2
    exit 1
fi

L=$HOME/Library
tmp=$(getconf DARWIN_USER_TEMP_DIR)
# Bundle-keyed: defaults (the sidebar's are a domain per config folder), caches, browser data, saved windows.
domains="$id $(cd "$L/Preferences" && ls -d "$id".sidebar.*.plist 2>/dev/null | sed 's/\.plist$//' | tr '\n' ' ')"
# One path a line: some hold spaces.
paths="$L/Caches/$id
$L/WebKit/$id
$L/HTTPStorages/$id
$L/HTTPStorages/$id.binarycookies
$L/Cookies/$id.binarycookies
$L/Application Support/$id
$L/Saved Application State/$id.savedState
${tmp%/}/$id.savedState"
# Folders named after the build, not the bundle id. A Release build other than the installed app (`make app`,
# `dev.ovvi.app.release`) shares the installed app's, so it keeps them. ~/.local/state/ovvi holds the cards' state on
# This Mac's herdr sessions, not the sessions.
case $id in
dev.ovvi.app.debug) paths="$paths
$HOME/.config/ovvi-dev
$L/Logs/Ovvi Dev" ;;
dev.ovvi.app) paths="$paths
$HOME/.config/ovvi
$L/Logs/Ovvi
$L/Caches/ovvi
$HOME/.cache/ovvi
$HOME/.local/state/ovvi" ;;
esac

for domain in $domains; do
    defaults read "$domain" >/dev/null 2>&1 || continue
    echo "defaults delete $domain"
    [ -n "$dry" ] || defaults delete "$domain"
done
echo "$paths" | while IFS= read -r path; do
    [ -e "$path" ] || continue
    echo "rm -rf $path"
    [ -n "$dry" ] || rm -rf "$path"
done
[ -z "$dry" ] || echo "(dry run: nothing deleted)"
