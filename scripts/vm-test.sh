#!/usr/bin/env bash
# Usage: scripts/vm-test.sh <derived data> <xcodebuild test arguments>...   (make vm-e2e calls it)
# Runs UI tests in the one Tart VM, ovvi-test, so they never take this Mac's pointer or keyboard. The VM runs this
# Mac's build (build-for-testing) and this Mac's Xcode, shared from the Mac: nothing is built or installed in it.
set -euo pipefail
cd "$(dirname "$0")/.."
dd=$1
shift
vm=ovvi-test runs=/tmp/ovvi-vm lock=/tmp/ovvi-vm.lock
command -v ovvi-tart >/dev/null || { echo "ovvi-tart is missing: install the Tart VM plugin (playbook/ci.md)" >&2; exit 1; }
tart list --source local --quiet | grep -qx "$vm" || { echo "no VM $vm: tart clone golden-gate $vm" >&2; exit 1; }

# One run at a time. The owner's pid makes a lock stale by itself once that run is gone.
until mkdir "$lock" 2>/dev/null; do
    owner=$(cat "$lock/owner" 2>/dev/null || true)
    if [[ -n $owner ]] && ! kill -0 "${owner%% *}" 2>/dev/null; then
        echo "removing the stale VM lock of '$owner'" >&2
        rm -rf "$lock"
        continue
    fi
    echo "the VM is busy: ${owner:-starting}; waiting" >&2
    sleep 5
done
run=$runs/runs/$$
trap 'rm -rf "$lock" "$run"' EXIT
echo "$$ ${OWNER:-$USER} $(date +%H:%M)" >"$lock/owner"

# The shares are set when the VM boots (ovvi-tart keeps them for its later starts).
xcode=$(dirname "$(dirname "$(xcode-select -p)")")
mkdir -p "$run"
ovvi-tart start "$vm" "--dir=xcode:$xcode:ro" "--dir=runs:$runs/runs" >/dev/null
until tart exec "$vm" true 2>/dev/null; do sleep 1; done
guest="/Volumes/My Shared Files"
tart exec "$vm" test -d "$guest/runs/$$" ||
    { echo "$vm runs without the test shares: tart stop $vm, then run again" >&2; exit 1; }
# Once per VM, and again after an Xcode update: the shared Xcode is the guest's Xcode.
tart exec "$vm" zsh -c "[[ \$(readlink /Applications/Xcode.app) == '$guest/xcode' ]] && xcodebuild -checkFirstLaunchStatus ||
    { sudo ln -sfn '$guest/xcode' /Applications/Xcode.app && sudo xcode-select -s /Applications/Xcode.app &&
      sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch; }" >/dev/null

# APFS clones: instant, and the next build cannot change a run under way.
cp -cR "$dd/Build/Products" scripts "$run/"
mkdir "$run/bin"
cp -c "$(command -v herdr)" "$run/bin/"
rm -rf "$dd/vm.xcresult"
status=0
tart exec "$vm" zsh -c "cd '$guest/runs/$$' && PATH=\$PWD/bin:\$PATH scripts/e2e.sh xcodebuild test-without-building \
    -xctestrun Products/*.xctestrun -destination platform=macOS -resultBundlePath vm.xcresult $(printf '%q ' "$@")" ||
    status=$?
mv "$run/vm.xcresult" "$dd/" 2>/dev/null && echo "result: $dd/vm.xcresult" >&2
exit $status
