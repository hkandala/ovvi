#!/usr/bin/env bash
# The docs' pictures (docs/public/images/*.png), dark, at 2x: the welcome scene (scripts/welcome-scene.sh) in the Tart
# VM on a 1280 x 800 pt screen at 2x (scripts/hidpi-display.m), never on this Mac's screen: it clicks and types.
#
#   scripts/docs-pictures.sh [<derived data>]   # after `make build DERIVED_DATA=…`; about 3 minutes
#
# It takes the VM lock for the run (playbook/workflow.md). Unlike a test run, it waits up to 30 minutes for a run that
# holds it: the pictures are taken by hand, rarely. The guest is set up as `make vm-e2e` leaves it (the shared Xcode).
set -euo pipefail
world=docs-pictures

if [[ ${1:-} != --in-vm ]]; then
    dd=${1:-${DERIVED_DATA:-/tmp/ovvi-dd-docs}} vm=ovvi-test runs=/tmp/ovvi-vm/runs locks=~/.config/ovvi-tart/locks
    app="$dd/Build/Products/Debug/Ovvi Debug.app"
    [ -d "$app" ] || { echo "no $app: make build DERIVED_DATA=$dd" >&2; exit 1; }
    app=$(cd "$app" && pwd)
    mkdir -p "$locks"
    [[ -n ${DOCS_LOCKED:-} ]] || DOCS_LOCKED=1 exec lockf -k -t 1800 "$locks/ovvi-test.lock" "$0" "$@"
    cd "$(dirname "$0")/.."
    echo "${OWNER:-$USER} docs-pictures $(date +%H:%M)" >"$locks/ovvi-test.owner"
    run=$runs/docs-$$ guest="/Volumes/My Shared Files"
    trap 'rm -rf "$run" "$locks/ovvi-test.owner"' EXIT
    mkdir -p "$run/bin" "$run/shots"
    cp -cR "$app" scripts "$run/"
    cp -c "$(command -v herdr)" "$run/bin/"
    clang -fobjc-arc -framework Foundation -framework CoreGraphics scripts/hidpi-display.m -o "$run/bin/hidpi-display"
    # As vm-test.sh: the VM up, and its shares mounted again when a resume left them stale.
    plugins/extra/tart-vm/bin/ovvi-tart start "$vm" "--dir=xcode:$(dirname "$(dirname "$(xcode-select -p)")"):ro" \
        "--dir=runs:$runs" >/dev/null
    for _ in $(seq 60); do tart exec "$vm" true 2>/dev/null && break; sleep 1; done
    tart exec "$vm" test -d "$guest/runs/docs-$$" || tart exec "$vm" zsh -c "sudo /sbin/umount -f '$guest' 2>/dev/null
        sudo mkdir -p '$guest' && sudo /sbin/mount_virtiofs com.apple.virtio-fs.automount '$guest'"
    status=0
    tart exec "$vm" zsh -lc "cd '$guest/runs/docs-$$' && PATH=\$PWD/bin:\$PATH scripts/docs-pictures.sh --in-vm" ||
        status=$?
    cp "$run"/shots/*.png docs/public/images/ 2>/dev/null || true
    exit $status
fi

# In the guest, in the run's copy of the checkout.
cd "$(dirname "$0")/.."
scene=scripts/welcome-scene.sh W=/tmp/$world
shot() {
    ax front
    "$scene" shot "$world" "$1" >/dev/null
    cp "$W/shots/$1-dark.png" "shots/$1.png"
}
# The display ends with this script.
hidpi-display 1280 800 >/tmp/docs-hidpi.log 2>&1 &
trap 'source "$W/scene.env" 2>/dev/null && "$scene" down "$world" "$S"' EXIT
for _ in $(seq 50); do grep -q . /tmp/docs-hidpi.log && break; sleep 0.2; done
grep -q ready /tmp/docs-hidpi.log || { cat /tmp/docs-hidpi.log >&2; exit 1; }

OVVI_APP="$PWD/Ovvi Debug.app" "$scene" up "$world" docs dark 1200x680
source "$W/scene.env"
ax() { "$W/tools/ax" "$pid" "$@"; }
sleep 3
shot window
# A card alone: a click on its title makes it the active pane, which shows its buttons; its zoom fills the tab.
zoom() {
    "$scene" click "$world" "pane.$1.title"
    ax press "pane.$1.zoom"
    sleep 1
}
zoom "$c1"
shot chat-view
ax press "pane.$c1.zoom"
zoom "$b"
shot browser
ax press "pane.$b.zoom"
# The tabs of w1 do not all fit: a press needs no place on screen. The overview shows a snapshot of each tab seen.
for tab in t2 t3 t4; do
    ax press "tab.w1:$tab"
    sleep 1
done
zoom "$g"
ax press 'title:Git Home'
sleep 2
shot git
ax press "pane.$g.zoom"
# The tab's one card: File Explorer.
ax press tab.w1:t5
sleep 1
"$scene" click "$world" "pane.$f.title"
ax press 'title:File Tree'
sleep 1
shot file-explorer
"$scene" click "$world" w5
ax press titlebar.new-tab
for _ in $(seq 50); do ax find 'pane.*' | grep -q '\.chooser\.' && break; sleep 0.2; done
ax find 'pane.*' | grep -q '\.chooser\.' || { echo "no New Pane list" >&2; exit 1; }
shot new-pane
"$scene" click "$world" w1
"$scene" click "$world" sidebar.overview
sleep 2
shot overview
"$scene" click "$world" overview.close
sleep 1
ax press 'title:Command Palette'
sleep 1
shot palette
ax press 'title:Settings…'
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
