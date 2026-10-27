#!/bin/bash
# Unpack darwin-vm's prebuilt iOS sysroot (bash, coreutils, ...) and print the
# CDHash of every Mach-O in it ("unsigned" if it has no code signature).
L=${ASOFT26_LINUX:-/root/ios26}
S=$L/sysroot
rm -rf $S && mkdir -p $S
tar xzf "${SYSROOT_TAR:?set SYSROOT_TAR to sysroot/ios_sysroot.tar.gz of jprx/darwin-vm}" -C $S --strip-components 1
find $S -type f -perm -u+x | sort | xargs python3 "$(dirname "$0")/cdhash.py" | sed "s|$S||" > $L/sysroot.cdhash
grep -c unsigned $L/sysroot.cdhash
wc -l < $L/sysroot.cdhash
grep -E '/bin/(bash|sh|ls|uname)$' $L/sysroot.cdhash
du -sh $S
