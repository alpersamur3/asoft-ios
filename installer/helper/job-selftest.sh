#!/bin/bash
# Helper job selftest: do the tools run, and can the IPSW (disk serial ipsw, if given)
# be read? A quick check before the long build-root job.
set -uo pipefail
rc=0
check() {
    local out
    if out=$("$@" 2>&1); then
        echo "ASOFT: ok   $*"
    else
        echo "ASOFT: FAIL $*: $(echo "$out" | head -3 | tr '\n' ' ')"
        rc=1
    fi
}
check python3 -c 'import plistlib, zipfile, zlib, struct'
# apfs-fuse has no --version; without arguments it prints its usage and exits 1,
# but a missing library shows up there
out=$(apfs-fuse 2>&1)
case $out in *"apfs-fuse [options]"*) echo "ASOFT: ok   apfs-fuse";; *) echo "ASOFT: FAIL apfs-fuse: $out"; rc=1;; esac
check test -x /usr/sbin/mkfs.hfsplus
check test -x /usr/sbin/fsck.hfsplus
check rsync --version
check losetup --version
check grep -q hfsplus /proc/filesystems
check grep -q fuse /proc/filesystems
check test -c /dev/fuse
for d in /sys/block/vd*; do
    [ -e "$d" ] && echo "ASOFT: disk ${d##*/} serial $(cat "$d/serial" 2>/dev/null) $(( $(cat "$d/size") >> 21 )) GiB"
done
for d in /sys/block/vd*; do
    if [ "$(cat "$d/serial" 2>/dev/null)" = ipsw ]; then
        python3 /asoft/ipsw-members.py "/dev/${d##*/}" | sed 's/^/ASOFT: ipsw /' || rc=1
    fi
done
exit $rc
