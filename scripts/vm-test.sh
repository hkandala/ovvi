#!/usr/bin/env bash
# Usage: scripts/vm-test.sh <derived data> <xcodebuild test arguments>...   (make vm-e2e calls it)
# Runs UI tests in the one Tart VM, ovvi-test, so they never take this Mac's pointer or keyboard. The VM runs this
# Mac's build (build-for-testing) and this Mac's Xcode, shared from the Mac: nothing is built or installed in it.
set -euo pipefail
# The VM lock: this repo's, for its agents (playbook/workflow.md); the Tart VM plugin knows nothing of it.
locks=~/.config/ovvi-tart/locks
lock=$locks/ovvi-test.lock owner=$locks/ovvi-test.owner
mkdir -p "$locks"
# One run at a time, and no queue: a busy VM sends the tests to CI (playbook/workflow.md). The kernel frees the lock
# when the run ends, also when it is killed.
if [[ -z ${VM_LOCKED:-} ]]; then
    # -k everywhere: lockf without it deletes the file, and a later run would lock a new one beside the held one.
    lockf -k -s -t 0 "$lock" true ||
        { echo "the VM is busy: $(cat "$owner" 2>/dev/null); run the tests on CI (ci.md)" >&2; exit 75; }
    VM_LOCKED=1 exec lockf -k -t 0 "$lock" "$0" "$@"
fi
cd "$(dirname "$0")/.."
dd=$1
shift
vm=ovvi-test runs=/tmp/ovvi-vm
for tool in tart herdr jq; do
    command -v $tool >/dev/null || { echo "$tool is missing (playbook/ci.md, The VM)" >&2; exit 1; }
done
tart list --source local --quiet | grep -qx "$vm" || { echo "no VM $vm: tart clone golden-gate $vm" >&2; exit 1; }
echo "${OWNER:-$USER} $$ $(date +%H:%M)" >"$owner"
run=$runs/runs/$$ guest="/Volumes/My Shared Files"
# What a run leaves in the guest, also a killed one: the app and herdr servers it started, and xcodebuild's folder
# for its products' path (a new one per run). The guest's disk is the VM's own.
tidy() {
    tart exec "$vm" zsh -c "pgrep -f '$guest/runs/|/bin/herdr --session ovvi-e2e-' | xargs kill 2>/dev/null
        rm -rf ~/Library/Developer/Xcode/DerivedData/Ovvi-*" || true
}
trap 'tidy; rm -rf "$run" "$owner"' EXIT
trap 'exit 143' TERM INT HUP

# The shares are set when the VM boots (ovvi-tart keeps them for its later starts).
xcode=$(dirname "$(dirname "$(xcode-select -p)")")
mkdir -p "$run"
# The Tart VM plugin's CLI, from this tree: nothing to install.
plugins/extra/tart-vm/bin/ovvi-tart start "$vm" "--dir=xcode:$xcode:ro" "--dir=runs:$runs/runs" >/dev/null
for _ in $(seq 60); do tart exec "$vm" true 2>/dev/null && break; sleep 1; done
tart exec "$vm" true || { echo "$vm: tart exec does not answer" >&2; exit 1; }
tidy
# A full guest disk kills the test runner (a low-space purge): stop before that.
free=$(tart exec "$vm" df -m /System/Volumes/Data | awk 'NR == 2 { print $4 }')
((free > 8000)) || { echo "$vm has $free MB free, under 8 GB: free space in it, or grow its disk (ci.md)" >&2; exit 1; }
# A resumed VM (suspended, then run again) keeps the guest's cached lookups in the shares from before the suspend, and
# they are wrong for the new shares: xcodebuild, seen before, is "No such file". Mounting the shares again drops them.
live="test -x '$guest/xcode/Contents/Developer/usr/bin/xcodebuild' -a -d '$guest/runs/$$'"
tart exec "$vm" zsh -c "$live" || tart exec "$vm" zsh -c "sudo /sbin/umount -f '$guest' 2>/dev/null; sudo mkdir -p '$guest' &&
    sudo /sbin/mount_virtiofs com.apple.virtio-fs.automount '$guest' && $live" ||
    { echo "$vm runs without the test shares: tart stop $vm, then run again" >&2; exit 1; }
# Once per VM, and again after an Xcode update: the shared Xcode is the guest's Xcode.
tart exec "$vm" zsh -c "[[ \$(readlink /Applications/Xcode.app) == '$guest/xcode' ]] && xcodebuild -checkFirstLaunchStatus ||
    { sudo ln -sfn '$guest/xcode' /Applications/Xcode.app && sudo xcode-select -s /Applications/Xcode.app &&
      sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch; }" >/dev/null
# /usr/bin/git finds the shared Xcode's git through xcrun, which takes about 9 s over the share until xcrun's cache in
# the guest's temporary folder (emptied at each boot) has it: longer than the app's 5 s for a git root. Found here,
# ahead of the tests.
tart exec "$vm" git --version >/dev/null

# APFS clones: instant, and the next build cannot change a run under way.
cp -cR "$dd/Build/Products" scripts OvviUITests/Fixtures "$run/"
mkdir "$run/bin"
cp -c "$(command -v herdr)" "$run/bin/"
# The tests find their fixtures and scripts by this checkout's path (#filePath): the same path in the guest leads to the
# run's copies.
tart exec "$vm" sudo zsh -c "mkdir -p '$PWD/OvviUITests' &&
    ln -sfn '$guest/runs/$$/Fixtures' '$PWD/OvviUITests/Fixtures' && ln -sfn '$guest/runs/$$/scripts' '$PWD/scripts'"
# The coding agents' stand-ins on the login shell's PATH, as on CI (ci.yml): the chooser looks for the agents there.
tart exec "$vm" zsh -c "ln -sfn '$guest/runs/$$/Fixtures/agents' ~/ovvi-agents && { grep -qs ovvi-agents ~/.zshrc ||
    echo 'export PATH=\"\$PATH:\$HOME/ovvi-agents:\$HOME/ovvi-agents/codex\"' | tee -a ~/.zshrc >>~/.bash_profile; }"
# A system alert takes the tests' clicks: close an open one (UserNotificationCenter's), and answer the asks that would
# come (scripts/vm-alerts.py).
tart exec "$vm" zsh -c "cd '$guest/runs/$$' && python3 scripts/vm-alerts.py >&2
    kill \$(pgrep -x UserNotificationCenter) 2>/dev/null && echo 'closed a system alert in $vm' >&2; true"
rm -rf "$dd/vm.xcresult"
# The newest: an Xcode or SDK update leaves the old one beside it.
xctestrun=$(cd "$run/Products" && ls -t ./*.xctestrun | head -1)
status=0
tart exec "$vm" zsh -c "cd '$guest/runs/$$' && PATH=\$PWD/bin:\$PATH scripts/e2e.sh xcodebuild test-without-building \
    -xctestrun Products/$xctestrun -destination platform=macOS -resultBundlePath vm.xcresult $(printf '%q ' "$@")" ||
    status=$?
mv "$run/vm.xcresult" "$dd/" 2>/dev/null && echo "result: $dd/vm.xcresult" >&2
exit $status
