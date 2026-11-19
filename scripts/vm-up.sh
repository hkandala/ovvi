# Sourced by vm-test.sh and docs-pictures.sh, under the VM lock, with $vm and $locks set.
# vm_up: boots the VM, or keeps the running one, with this Mac's Xcode and the runs folder shared (ovvi-tart keeps the
# shares for its later starts). Exit 75 sends the caller's tests to CI.
vm_up() {
    plugins/extra/tart-vm/bin/ovvi-tart start "$vm" "--dir=xcode:$(dirname "$(dirname "$(xcode-select -p)")"):ro" \
        --dir=runs:/tmp/ovvi-vm/runs >/dev/null ||
        { echo "$vm did not start (after \"exceeds the system limit\", only a reboot of the Mac helps): use CI" >&2
          exit 75; }
    for _ in $(seq 60); do tart exec "$vm" true 2>/dev/null && break; sleep 1; done
    tart exec "$vm" true || { echo "$vm: tart exec does not answer" >&2; exit 1; }
}
# vm_idle_stop, when the caller is done: the VM holds all its memory while it runs, idle too, so it stops 10 minutes
# later, unless a later use armed its own stop; while the lock is held then, it tries each minute. In a session of its
# own: a killed caller leaves it waiting.
vm_idle_stop() {
    touch "$locks/ovvi-test.last"
    perl -MPOSIX -e 'setsid; exec @ARGV' sh -c "sleep 600
        while [ \$(stat -f %m '$locks/ovvi-test.last') = $(stat -f %m "$locks/ovvi-test.last") ]; do
            lockf -k -t 0 '$locks/ovvi-test.lock' tart stop $vm; [ \$? = 75 ] || break; sleep 60
        done" >/dev/null 2>&1 </dev/null &
}
