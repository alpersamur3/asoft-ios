#!/bin/bash
# Make a qcow2 overlay of the root disk with some launchd jobs removed (the base image is not
# touched; delete the overlay to undo). Runs inside ios-emu:
#   wsl -d ios-emu -u root -- bash scripts/dev/make-slim-disk.sh \
#       NAME LABEL [LABEL ...]
# -> <work>\root\ios16-root-20H392-NAME.qcow2 (backing file: ios16-root-20H392.qcow2)
# Refuses to write when the HFS+ journal is not empty (Linux's hfsplus ignores the journal, and
# iOS would replay it over the change), or when a volume without a journal was not cleanly
# unmounted. (A journaled volume committed while iOS ran is never marked clean.)
set -euo pipefail

NAME=$1; shift
DIR=${ASOFT_WORK_WSL:-$(cd "$(dirname "$0")/../.." && pwd)/work}/root
BASE=ios16-root-20H392.qcow2
OVL=ios16-root-20H392-$NAME.qcow2
MNT=/mnt/iosroot-$NAME
NBD=/dev/nbd0

grep -q hfsplus /proc/filesystems || modprobe hfsplus
grep -q nbd /proc/devices || modprobe nbd max_part=0
cd "$DIR"
rm -f "$OVL"
qemu-img create -q -f qcow2 -b "$BASE" -F qcow2 "$OVL"
qemu-nbd --connect=$NBD "$OVL"
trap 'mountpoint -q $MNT && umount $MNT; qemu-nbd --disconnect $NBD >/dev/null' EXIT
sleep 1

python3 - $NBD <<'EOF'
import struct, sys
f = open(sys.argv[1], 'rb')
f.seek(1024)
vh = f.read(512)
sig, ver, attrs, _, jib = struct.unpack('>2sHI4sI', vh[:16])
block = struct.unpack('>I', vh[40:44])[0]
clean = bool(attrs & (1 << 8))
journaled = bool(attrs & (1 << 13))
print(f'volume {sig.decode()} v{ver} block {block}: clean unmount {clean}, journaled {journaled}')
if not clean and not journaled:
    sys.exit('volume not cleanly unmounted and has no journal: not touching it')
if journaled:
    f.seek(jib * block)
    ji = f.read(52)
    jflags, = struct.unpack('>I', ji[:4])
    joff, = struct.unpack('>Q', ji[36:44])
    f.seek(joff)
    jh = f.read(24)
    order = '<' if struct.unpack('<I', jh[:4])[0] == 0x4a4e4c78 else '>'   # written in host order
    magic, endian, start, end = struct.unpack(order + 'IIQQ', jh)
    print(f'journal: magic {magic:#x}, start {start}, end {end}')
    if magic != 0x4a4e4c78:
        sys.exit('no journal header where the info block points: not touching it')
    if start != end:
        sys.exit('journal has transactions iOS would replay: not touching it')
EOF

mkdir -p $MNT
mount -t hfsplus -o force $NBD $MNT
python3 - $MNT/System/Library/xpc/launchd.plist "$@" <<'EOF'
import plistlib, sys
path, labels = sys.argv[1], set(sys.argv[2:])
p = plistlib.load(open(path, 'rb'))
jobs = p['LaunchDaemons']
missing = labels - {j.get('Label') for j in jobs.values()}
if missing:
    sys.exit(f'jobs not found: {", ".join(sorted(missing))}')
gone = [k for k, j in jobs.items() if j.get('Label') in labels]
for k in gone:
    del jobs[k]
with open(path, 'wb') as f:
    plistlib.dump(p, f, fmt=plistlib.FMT_BINARY)
print(f'launchd.plist: removed {len(gone)} jobs: {", ".join(sorted(labels))}')
EOF
sync
umount $MNT
ls -lsh "$DIR/$OVL"
