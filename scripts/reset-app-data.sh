#!/bin/sh
# Deletes all of one Ovvi build's local data on this Mac, so it starts as on a fresh install.
# Usage: scripts/reset-app-data.sh [--dry-run] [bundle id]   (default dev.ovvi.app, the installed app)
# For the installed app it also deletes ~/.config/ovvi, plugins written with New Plugin included.
# Never touches herdr's sessions or their servers, nor ~/.pi, ~/.claude, ~/.codex or any agent's files.
# Run it as yourself: under sudo, HOME and the temporary folders are root's, and macOS's privacy protection blocks root
# too. Folders that protection guards need Full Disk Access for the terminal app; the script names what it kept.
set -eu

[ "$(id -u)" -ne 0 ] || {
    echo "run it without sudo: as root it would look in root's folders, not yours" >&2
    exit 2
}
dry=
[ "${1:-}" = --dry-run ] && { dry=1; shift; }
[ $# -le 1 ] || { echo "usage: $0 [--dry-run] [bundle id]" >&2; exit 2; }
id=${1:-dev.ovvi.app}
case $id in
*[!A-Za-z0-9.-]*) echo "not an Ovvi bundle id: $id" >&2; exit 2 ;;
dev.ovvi.app | dev.ovvi.app.*) ;;
*) echo "not an Ovvi bundle id: $id" >&2; exit 2 ;;
esac
# The installed app's reset deletes folders every build uses.
running=$(lsappinfo list | grep -o 'bundleID="dev\.ovvi\.app[A-Za-z0-9.-]*"' | tr -d '"' | sed 's/bundleID=//')
if [ "$id" = dev.ovvi.app ] && [ -n "$running" ] || echo "$running" | grep -qxF "$id"; then
    echo "an Ovvi build is running ($(echo $running)): quit it first" >&2
    exit 1
fi

L=$HOME/Library
tmp=$(getconf DARWIN_USER_TEMP_DIR) cache=$(getconf DARWIN_USER_CACHE_DIR)
# Bundle-keyed: defaults (the sidebar's are a domain per config folder), caches, browser data, saved windows.
domains="$id $(cd "$L/Preferences" && ls -d "$id".sidebar.*.plist 2>/dev/null | sed 's/\.plist$//' | tr '\n' ' ')"
# One path a line: some hold spaces. A launch with -ApplePersistenceIgnoreState saves its windows in $tmp.
paths="$L/Caches/$id
$L/WebKit/$id
$L/HTTPStorages/$id
$L/HTTPStorages/$id.binarycookies
$L/Cookies/$id.binarycookies
$L/Application Support/$id
$L/Saved Application State/$id.savedState
$tmp$id.savedState
$tmp$id
$cache$id"
for path in "$tmp"com.apple.WebKit.*+"$id" "$cache"com.apple.WebKit.*+"$id"; do
    paths="$paths
$path"
done
# macOS keeps an app's saved windows in talagentd's container, a folder per app named in ApplicationMapping.plist: an
# array of {protected: {signingIdentifier}} dictionaries, each followed by its folder's name.
kept=
ls "$L/Daemon Containers" >/dev/null 2>&1 || echo "macOS keeps the saved windows in ~/Library/Daemon Containers," \
    "which needs Full Disk Access; Ovvi closes them on its first launch."
for map in "$L/Daemon Containers"/*/Data/Library/"Saved Application State"/ApplicationMapping.plist; do
    i=0
    while folder=$(plutil -extract "$((i + 1))" raw -o - "$map" 2>/dev/null); do
        if [ "$(plutil -extract "$i.protected.signingIdentifier" raw -o - "$map" 2>/dev/null)" = "$id" ]; then
            paths="$paths
${map%/*}/$folder.savedState"
        fi
        i=$((i + 2))
    done
done
# Folders named after the build, not the bundle id. A Release build other than the installed app (`make app`,
# `dev.ovvi.app.release`) shares the installed app's, so it keeps them. ~/.local/state/ovvi holds the cards' state on
# This Mac's herdr sessions, not the sessions. A running herdr server goes on writing its log in ~/Library/Logs/Ovvi
# to the deleted file until it restarts.
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
# Not in a pipe: `kept` must outlive the loop, and one path macOS keeps must not end it. A path in a folder macOS
# guards (~/Library/Cookies) fails `-e` without a word: nothing to say about it.
while IFS= read -r path; do
    [ -e "$path" ] || continue
    echo "rm -rf $path"
    [ -n "$dry" ] || rm -rf "$path" 2>/dev/null || kept="$kept$path
"
done <<EOF
$paths
EOF
[ -z "$dry" ] || echo "(dry run: nothing deleted)"
[ -n "$kept" ] || exit 0
printf '\nKept, as macOS blocks this terminal from them:\n%s' "$kept" >&2
echo "To delete them too: System Settings > Privacy & Security > Full Disk Access, turn on your terminal app," \
    "reopen it, and run this again." >&2
exit 1
