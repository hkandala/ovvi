#!/usr/bin/env bash
# Usage: scripts/vm-test.sh <derived data> <xcodebuild test arguments>...   (make vm-e2e calls it)
# Runs UI tests in the one Tart VM, ovvi-test, so they never take this Mac's pointer or keyboard. The VM runs this
# Mac's build (build-for-testing) and this Mac's Xcode, shared from the Mac: nothing is built or installed in it.
set -euo pipefail
lock=/tmp/ovvi-vm.lock
# One run at a time: lockf waits for the lock, and the kernel frees it when the run ends, also when it is killed.
if [[ -z ${VM_LOCKED:-} ]]; then
    # -k everywhere: lockf without it deletes the file, and a later run would lock a new one beside the held one.
    lockf -k -s -t 0 "$lock" true || echo "the VM is busy: $(cat "$lock.owner" 2>/dev/null); waiting" >&2
    VM_LOCKED=1 exec lockf -k "$lock" "$0" "$@"
fi
cd "$(dirname "$0")/.."
dd=$1
shift
vm=ovvi-test runs=/tmp/ovvi-vm
for tool in tart herdr ovvi-tart; do
    command -v $tool >/dev/null || { echo "$tool is missing (playbook/ci.md, The VM)" >&2; exit 1; }
done
tart list --source local --quiet | grep -qx "$vm" || { echo "no VM $vm: tart clone golden-gate $vm" >&2; exit 1; }
echo "${OWNER:-$USER} $$ $(date +%H:%M)" >"$lock.owner"
run=$runs/runs/$$
trap 'rm -rf "$run" "$lock.owner"' EXIT

# The shares are set when the VM boots (ovvi-tart keeps them for its later starts).
xcode=$(dirname "$(dirname "$(xcode-select -p)")")
mkdir -p "$run"
ovvi-tart start "$vm" "--dir=xcode:$xcode:ro" "--dir=runs:$runs/runs" >/dev/null
for _ in $(seq 60); do tart exec "$vm" true 2>/dev/null && break; sleep 1; done
tart exec "$vm" true || { echo "$vm: tart exec does not answer" >&2; exit 1; }
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
# The newest: an Xcode or SDK update leaves the old one beside it.
xctestrun=$(cd "$run/Products" && ls -t ./*.xctestrun | head -1)
status=0
tart exec "$vm" zsh -c "cd '$guest/runs/$$' && PATH=\$PWD/bin:\$PATH scripts/e2e.sh xcodebuild test-without-building \
    -xctestrun Products/$xctestrun -destination platform=macOS -resultBundlePath vm.xcresult $(printf '%q ' "$@")" ||
    status=$?
mv "$run/vm.xcresult" "$dd/" 2>/dev/null && echo "result: $dd/vm.xcresult" >&2
exit $status
