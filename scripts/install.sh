#!/bin/sh
# Installs Ovvi, the macOS app for herdr, from its GitHub release:
#   curl -fsSL https://github.com/hkandala/ovvi/releases/latest/download/install.sh | sh
#   … | sh -s -- --version 0.1.0    that release
# It checks the download against the release's SHA256SUMS, asks before it links the ovvi skill for agents and before it
# installs herdr and herdr's agent integrations, and opens the app.
set -eu

die() {
    printf 'install.sh: %s\n' "$1" >&2
    exit 1
}

# A question to the terminal: stdin is the script itself. No terminal: no.
ask() {
    (: </dev/tty) 2>/dev/null || return 1
    printf '%s [y/N] ' "$1" >/dev/tty
    read -r answer </dev/tty || return 1
    case $answer in [yY]*) ;; *) return 1 ;; esac
}

# All in one function, so sh has read the whole script before it runs any of it: a cut-off download runs nothing, and
# no child reads the rest of the script from stdin.
main() {
    base=https://github.com/hkandala/ovvi/releases/latest/download
    while [ $# -gt 0 ]; do
        case $1 in
            --version)
                [ $# -ge 2 ] || die "--version needs a version, such as 0.1.0"
                base=https://github.com/hkandala/ovvi/releases/download/v${2#v}
                shift
                ;;
            *) die "unknown option $1 (use --version <version>)" ;;
        esac
        shift
    done

    [ "$(id -u)" -ne 0 ] || die "run it without sudo"
    [ "$(uname -s)" = Darwin ] || die "Ovvi runs on macOS only"
    [ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] || die "Ovvi needs a Mac with Apple silicon"
    major=$(sw_vers -productVersion | cut -d. -f1)
    [ "$major" -ge 26 ] || die "Ovvi needs macOS 26 or later (this Mac has $(sw_vers -productVersion))"

    tmp=$(mktemp -d)
    stage=
    trap 'rm -rf "$tmp" ${stage:+"$stage"}' EXIT
    curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS" || die "no release at $base"
    zip=$(awk '$2 ~ /^Ovvi-[A-Za-z0-9.-]+\.zip$/ { print $2; exit }' "$tmp/SHA256SUMS")
    [ -n "$zip" ] || die "the release's SHA256SUMS names no zip"
    echo "Downloading $zip"
    curl -fL --progress-bar -o "$tmp/$zip" "$base/$zip" || die "the download failed"
    (cd "$tmp" && grep " $zip\$" SHA256SUMS | shasum -a 256 -c -s) || die "$zip does not match SHA256SUMS"

    # An old copy is replaced where it is; a new one goes to /Applications, or ~/Applications when that is not
    # writable.
    dest=
    for d in /Applications "$HOME/Applications"; do
        if [ -d "$d/Ovvi.app" ]; then
            dest=$d
            break
        fi
    done
    if [ -z "$dest" ]; then
        if [ -w /Applications ]; then dest=/Applications; else dest=$HOME/Applications; fi
    fi
    mkdir -p "$dest"
    [ -w "$dest" ] || die "$dest is not writable"

    # The user quits it: a quit sent from here would be an Apple event, which macOS asks the user to allow first.
    if [ -n "$(lsappinfo find bundleid=dev.ovvi.app)" ]; then
        (: </dev/tty) 2>/dev/null || die "Ovvi is running: quit it, then run this again"
        echo "Ovvi is running. Quit it (⌘Q) to go on, or press Ctrl-C to stop: herdr keeps your sessions and agents."
        while [ -n "$(lsappinfo find bundleid=dev.ovvi.app)" ]; do sleep 1; done
    fi

    # Unpacked beside the old copy, so the swap is two renames on one volume.
    stage=$dest/.ovvi-install.$$
    ditto -x -k "$tmp/$zip" "$stage"
    [ -d "$stage/Ovvi.app" ] || die "$zip holds no Ovvi.app"
    if [ -e "$dest/Ovvi.app" ]; then mv "$dest/Ovvi.app" "$stage/old.app"; fi
    mv "$stage/Ovvi.app" "$dest/Ovvi.app" || {
        [ ! -e "$stage/old.app" ] || mv "$stage/old.app" "$dest/Ovvi.app"
        die "could not replace $dest/Ovvi.app"
    }
    echo "Installed $dest/Ovvi.app"

    # The ovvi skill teaches agents the `ovvi` command: pi, Codex and OpenCode read ~/.agents/skills, Claude Code
    # ~/.claude/skills. A link to the app's own copy, so each update of the app updates the skill. A skill that is
    # already there stays; a dangling link (the app moved) counts as none.
    agents=$HOME/.agents/skills claude=$HOME/.claude/skills
    if { [ ! -e "$agents/ovvi" ] || [ ! -e "$claude/ovvi" ]; } &&
        ask "Install the ovvi skill, so Claude Code, Codex, Pi and OpenCode know Ovvi's ovvi command?"; then
        mkdir -p "$agents" "$claude"
        [ -e "$agents/ovvi" ] || ln -sfn "$dest/Ovvi.app/Contents/Resources/skills/ovvi" "$agents/ovvi"
        [ -e "$claude/ovvi" ] || ln -sfn "$agents/ovvi" "$claude/ovvi"
    fi

    # Where herdr's own installer puts it.
    bin=${HERDR_INSTALL_DIR:-$HOME/.local/bin}
    herdr=$(command -v herdr || true)
    [ -n "$herdr" ] || [ ! -x "$bin/herdr" ] || herdr=$bin/herdr
    if [ -z "$herdr" ] && ask "Ovvi needs herdr, the terminal multiplexer. Install it from herdr.dev?"; then
        curl -fsSL https://herdr.dev/install.sh | sh || true
        [ ! -x "$bin/herdr" ] || herdr=$bin/herdr
        [ -n "$herdr" ] || echo "herdr did not install: Ovvi offers its install again in its window."
    fi
    if [ -n "$herdr" ]; then
        status=$("$herdr" integration status 2>/dev/null || true)
        for agent in claude:"Claude Code" codex:Codex pi:Pi opencode:OpenCode; do
            target=${agent%%:*} name=${agent#*:}
            command -v "$target" >/dev/null || continue
            case $(printf '%s\n' "$status" | grep "^$target:") in
                *": current"*) continue ;;
                *": outdated"*) verb=Update ;;
                *) verb=Install ;;
            esac
            if ask "$verb herdr's $name integration, so herdr knows when $name works or waits?"; then
                "$herdr" integration install "$target" </dev/null || echo "The $name integration did not install."
            fi
        done
    fi

    open "$dest/Ovvi.app"
    cat <<EOF

To uninstall Ovvi: quit it, then
  rm -rf "$dest/Ovvi.app" ~/.config/ovvi "\$HOME/Library/Logs/Ovvi"; defaults delete dev.ovvi.app
  rm -f ~/.agents/skills/ovvi ~/.claude/skills/ovvi   # the skill's links
herdr and its sessions stay; herdr's own docs say how to remove it.
EOF
}

main "$@"
