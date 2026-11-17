#!/usr/bin/env bash
# The docs' pictures (docs/public/images/*.png), dark, at 2x: the welcome scene (scripts/welcome-scene.sh) in the Tart
# VM on a 1280 x 800 pt screen at 2x (scripts/hidpi-display.m), never on this Mac's screen: it clicks and types.
#
#   scripts/docs-pictures.sh [<derived data>]   # after `make build DERIVED_DATA=…`; about 3 minutes
#
# It takes the VM lock for the run (playbook/workflow.md) and stops at once when another run holds it.
set -euo pipefail
cd "$(dirname "$0")/.."
world=docs-pictures

if [[ ${1:-} != --in-vm ]]; then
    dd=${1:-${DERIVED_DATA:-/tmp/ovvi-dd-docs}} vm=ovvi-test runs=/tmp/ovvi-vm/runs locks=~/.config/ovvi-tart/locks
    app="$dd/Build/Products/Debug/Ovvi Debug.app"
    [ -d "$app" ] || { echo "no $app: make build DERIVED_DATA=$dd" >&2; exit 1; }
    run=$runs/docs-$$
    trap 'rm -rf "$run"' EXIT
    mkdir -p "$run/bin" "$run/shots"
    cp -cR "$app" scripts "$run/"
    cp -c "$(command -v herdr)" "$run/bin/"
    plugins/extra/tart-vm/bin/ovvi-tart start "$vm" "--dir=xcode:$(dirname "$(dirname "$(xcode-select -p)")"):ro" \
        "--dir=runs:$runs" >/dev/null
    lockf -k -t 0 "$locks/ovvi-test.lock" sh -c "echo '${OWNER:-$USER} docs-pictures' >'$locks/ovvi-test.owner'
        tart exec $vm zsh -lc \"cd '/Volumes/My Shared Files/runs/docs-$$' && PATH=\\\$PWD/bin:\\\$PATH \
            scripts/docs-pictures.sh --in-vm\"" || { echo "the VM is busy or the run failed" >&2; exit 1; }
    cp "$run"/shots/*.png docs/public/images/
    exit
fi

# In the guest.
scene=scripts/welcome-scene.sh W=/tmp/$world
key() { osascript -e "tell application \"System Events\" to $1"; }
shot() {
    "$scene" shot "$world" "$1" >/dev/null
    cp "$W/shots/$1-dark.png" "shots/$1.png"
}
clang -fobjc-arc -framework Foundation -framework CoreGraphics scripts/hidpi-display.m -o /tmp/hidpi-display
rm -f /tmp/docs-hidpi && mkfifo /tmp/docs-hidpi
/tmp/hidpi-display 1280 800 </tmp/docs-hidpi >/tmp/docs-hidpi.log 2>&1 &
exec 3>/tmp/docs-hidpi
trap 'source "$W/scene.env" 2>/dev/null && "$scene" down "$world" "$S"; exec 3>&-' EXIT
for _ in $(seq 50); do grep -q ready /tmp/docs-hidpi.log && break; sleep 0.2; done
grep -q ready /tmp/docs-hidpi.log || { cat /tmp/docs-hidpi.log >&2; exit 1; }

OVVI_APP="$PWD/Ovvi Debug.app" "$scene" up "$world" docs dark 1200x720
source "$W/scene.env"
ax() { "$W/tools/ax" "$pid" "$@"; }
sleep 3
shot window
"$scene" click "$world" "pane.$c1.zoom"
sleep 1
shot chat-view
key 'keystroke return using {shift down, command down}'
browser=$(ax find 'pane.w1:p*' | cut -d' ' -f1 | grep -xE 'pane\.w1:p[0-9]+' | grep -vx "pane.$c1" | head -1)
"$scene" click "$world" "$browser"
key 'keystroke return using {shift down, command down}'
sleep 1
shot browser
key 'keystroke return using {shift down, command down}'
"$scene" click "$world" w1:t4
sleep 2
shot git
"$scene" click "$world" w1:t5
sleep 2
shot file-explorer
"$scene" click "$world" w5
"$scene" click "$world" titlebar.new-tab
sleep 1
shot new-pane
key 'key code 53'
"$scene" click "$world" w1
"$scene" click "$world" sidebar.overview
sleep 2
shot overview
key 'key code 53'
sleep 1
key 'keystroke "k" using command down'
sleep 1
shot palette
key 'key code 53'
key 'keystroke "," using command down'
"$scene" click "$world" settings.page.appearance
ax park
sleep 1
screencapture -x -o -l "$(ax windows | sed -n 2p | cut -d' ' -f1)" shots/settings.png

# The welcome, as at a first launch: no window until it ends.
kill "$pid"
for _ in $(seq 50); do ps -p "$pid" >/dev/null || break; sleep 0.2; done
H=$(readlink "$W/home")
open -n "$PWD/Ovvi Debug.app" --env HOME="$H" --env CFFIXED_USER_HOME="$H" --env XDG_CONFIG_HOME="$W/xdg" \
    --args -session "$S" -configFolder "$W/config" -archivedHome "$W/archived" -welcomeDone NO -appearance dark \
    -liquidGlass YES -ApplePersistenceIgnoreState YES
for _ in $(seq 100); do
    pid=$(pgrep -f "/Contents/MacOS/Ovvi -session $S " || true)
    [ -n "$pid" ] && ax windows | grep -q . && break
    sleep 0.2
done
sleep 4
ax park
screencapture -x -o -l "$(ax windows | head -1 | cut -d' ' -f1)" shots/welcome.png
printf 'pid=%q\n' "$pid" >>"$W/scene.env"
