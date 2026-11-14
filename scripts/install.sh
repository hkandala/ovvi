#!/bin/sh
# Installs Ovvi, the macOS app for herdr, from its GitHub release:
#   curl -fsSL https://github.com/hkandala/ovvi/releases/latest/download/install.sh | sh
#   … | sh -s -- --dev              Ovvi Tip, the dev build of the newest main, beside Ovvi
#   … | sh -s -- --version 0.1.0    that release
# It checks the download against the release's SHA256SUMS, asks before it installs herdr and herdr's agent
# integrations, and opens the app.
set -eu
repo=https://github.com/hkandala/ovvi
base=$repo/releases/latest/download app=Ovvi id=dev.ovvi.app config=ovvi

die() { printf 'install.sh: %s\n' "$1" >&2; exit 1; }
# A question to the terminal: stdin is the script itself. No terminal: no.
ask() {
    (: </dev/tty) 2>/dev/null || return 1
    printf '%s [y/N] ' "$1" >/dev/tty
    read -r answer </dev/tty || return 1
    case $answer in [yY]*) ;; *) return 1 ;; esac
}

while [ $# -gt 0 ]; do
    case $1 in
        --dev) base=$repo/releases/download/tip app="Ovvi Tip" id=dev.ovvi.app.tip config=ovvi-tip ;;
        --version)
            [ $# -ge 2 ] || die "--version needs a version, such as 0.1.0"
            base=$repo/releases/download/v${2#v} app=Ovvi id=dev.ovvi.app config=ovvi
            shift ;;
        *) die "unknown option $1 (use --dev or --version <version>)" ;;
    esac
    shift
done

[ "$(uname -s)" = Darwin ] || die "Ovvi runs on macOS only"
[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] || die "Ovvi needs a Mac with Apple silicon"
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 26 ] || die "Ovvi needs macOS 26 or later (this Mac has $(sw_vers -productVersion))"

tmp=$(mktemp -d)
stage=
trap 'rm -rf "$tmp" ${stage:+"$stage"}' EXIT
curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS" || die "no release at $base"
zip=$(awk '$2 ~ /^Ovvi[A-Za-z0-9._-]*\.zip$/ { print $2; exit }' "$tmp/SHA256SUMS")
[ -n "$zip" ] || die "the release's SHA256SUMS names no zip"
echo "Downloading $zip"
curl -fL --progress-bar -o "$tmp/$zip" "$base/$zip" || die "the download failed"
(cd "$tmp" && grep " $zip\$" SHA256SUMS | shasum -a 256 -c -s) || die "$zip does not match SHA256SUMS"

# An old copy is replaced where it is; a new one goes to /Applications, or ~/Applications when that is not writable.
dest=
for d in /Applications "$HOME/Applications"; do
    if [ -d "$d/$app.app" ]; then dest=$d; break; fi
done
if [ -z "$dest" ]; then
    if [ -w /Applications ]; then dest=/Applications; else dest=$HOME/Applications; fi
fi
mkdir -p "$dest"
[ -w "$dest" ] || die "$dest is not writable"

if [ -n "$(lsappinfo find bundleid="$id")" ]; then
    ask "$app is running. Quit it to install? herdr keeps your sessions and agents." ||
        die "quit $app, then run this again"
    osascript -e "tell application id \"$id\" to quit" >/dev/null || die "quit $app, then run this again"
    i=0
    while [ -n "$(lsappinfo find bundleid="$id")" ]; do
        i=$((i + 1))
        [ $i -le 30 ] || die "$app did not quit"
        sleep 1
    done
fi

# Unpacked beside the old copy, so the swap is two renames on one volume.
stage=$dest/.ovvi-install.$$
ditto -x -k "$tmp/$zip" "$stage"
[ -d "$stage/$app.app" ] || die "$zip holds no $app.app"
if [ -e "$dest/$app.app" ]; then mv "$dest/$app.app" "$stage/old.app"; fi
mv "$stage/$app.app" "$dest/$app.app" || { mv "$stage/old.app" "$dest/$app.app"; die "could not replace $dest/$app.app"; }
echo "Installed $dest/$app.app"

herdr=$(command -v herdr || true)
[ -n "$herdr" ] || [ ! -x "$HOME/.local/bin/herdr" ] || herdr=$HOME/.local/bin/herdr
if [ -z "$herdr" ] && ask "Ovvi needs herdr, the terminal multiplexer. Install it from herdr.dev?"; then
    curl -fsSL https://herdr.dev/install.sh | sh && herdr=$HOME/.local/bin/herdr
fi
if [ -n "$herdr" ]; then
    status=$("$herdr" integration status 2>/dev/null || true)
    for agent in claude:"Claude Code" codex:Codex pi:Pi opencode:OpenCode; do
        target=${agent%%:*} name=${agent#*:}
        case $(printf '%s\n' "$status" | grep "^$target:") in *": current"*) continue ;; esac
        if ask "Install herdr's $name integration, so herdr knows when $name works or waits?"; then
            "$herdr" integration install "$target" || echo "The $name integration did not install."
        fi
    done
fi

open "$dest/$app.app"
cat <<EOF

To uninstall $app: quit it, then
  rm -rf "$dest/$app.app" ~/.config/$config "\$HOME/Library/Logs/$app"; defaults delete $id
herdr and its sessions stay; herdr's own docs say how to remove it.
EOF
