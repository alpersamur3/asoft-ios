#!/bin/bash
# Build the iOS 26 root disk for -M vresearch (M2), in WSL as root: one
# case-sensitive, journaled HFS+ volume (whole disk, no partition map) holding
# the iPhone OS root filesystem plus its two cryptexes, in a qcow2 on C:.
# Same layout as Yol A's tools/mkiosroot.sh (iOS 16), which this follows:
#   - the cryptexes live in /private/preboot/Cryptexes/{OS,App}
#   - /System/Library/Caches/com.apple.dyld hard-links the SystemOS shared cache
#   - every cryptex file the OS root lacks is hard-linked to its root path
#   - logd's stores exist with the owner/mode/marker logd checks
# Plus darwin-vm's sysroot (bash, coreutils, ...), ad-hoc signed, without
# overwriting anything Apple's; its CDHashes go to $OUT.hashes.
# Left out to save space on C: (data, not code; empty directories remain):
# $EXCLUDE. With DROP_SYSOS=1 the decrypted SystemOS image is deleted once
# copied, before the OS (it comes back from its .aea with ipsw fw aea).
#
#   mk-root26.sh
# env: OS SYSOS APPOS (decrypted images), OUT (qcow2), SIZE, NBD (>= /dev/nbd12),
#      EXCLUDE, DROP_SYSOS
set -euo pipefail
A=${ASOFT26:?set ASOFT26 to the build folder as WSL sees it, e.g. /mnt/d/ios26}
L=${ASOFT26_LINUX:-/root/ios26}
S=$(cd "$(dirname "$0")" && pwd)
OS=${OS:-$A/os/094-97246-090.dmg}
SYSOS=${SYSOS:-$A/os/094-95368-092.dmg}
APPOS=${APPOS:-$A/iphone/094-96441-094.dmg}
OUT=${OUT:-$A/root26.qcow2}
SIZE=${SIZE:-32G}
NBD=${NBD:-/dev/nbd12}
SYSROOT=$L/sysroot
EXCLUDE=${EXCLUDE:-/private/var/staged_system_apps /System/Library/LinguisticData /System/Library/PreinstalledAssetsV2 /System/Library/NanoTimeKit /usr/standalone}

case $NBD in /dev/nbd1[2-9]|/dev/nbd[2-9][0-9]) ;; *) echo "use /dev/nbd12 or higher"; exit 1;; esac
[[ ! -e $OUT ]] || { echo "refusing to overwrite $OUT"; exit 1; }
[[ ! -s /sys/block/${NBD#/dev/}/pid ]] || { echo "$NBD is in use"; exit 1; }

work=/tmp/mkroot26		# mount points only
mkdir -p $work
mounts=()
cleanup() {
	for m in "${mounts[@]}"; do
		mountpoint -q "$m" && { umount "$m" 2> /dev/null || fusermount -u "$m" 2> /dev/null || true; }
	done
	qemu-nbd -d $NBD > /dev/null 2>&1 || true
}
trap cleanup EXIT

# apfs-fuse parses UDIF only when the name ends in .dmg (the OS image is UDIF,
# the cryptexes raw APFS); links also keep ',' out of its option parsing.
apfs_mount() {
	ln -sfn "$1" $work/$2.dmg
	mkdir -p $work/$2
	apfs-fuse -o allow_other $work/$2.dmg $work/$2
	mounts+=($work/$2)
}
apfs_mount "$OS" os
apfs_mount "$SYSOS" sysos
apfs_mount "$APPOS" appos
src() { [ -d $work/$1/root ] && echo $work/$1/root || echo $work/$1; }

mkdir -p "$(dirname "$OUT")"
qemu-img create -q -f qcow2 "$OUT" $SIZE
modprobe nbd max_part=0 2> /dev/null || true
# the WSL kernel has no hfsplus; same module and check as the iOS 16 session's tools
grep -q hfsplus /proc/filesystems || modprobe hfsplus 2>/dev/null || insmod "${HFSPLUS_KO:?WSL has no hfsplus module: build it and set HFSPLUS_KO}"
qemu-nbd -f qcow2 --cache=writeback -c $NBD "$OUT"
sleep 1
mkfs.hfsplus -s -J -v iOSRoot $NBD > /dev/null
mkdir -p $work/root
mount -t hfsplus -o force $NBD $work/root
mounts=($work/root "${mounts[@]}")
R=$work/root

copy() {
	echo "$(date +%T) copying $1 -> /${2#"$R"}"
	mkdir -p "$2"
	rsync -aH --numeric-ids "${@:3}" "$1/" "$2/"
}
copy "$(src sysos)" $R/private/preboot/Cryptexes/OS
copy "$(src appos)" $R/private/preboot/Cryptexes/App
if [ "${DROP_SYSOS:-0}" = 1 ]; then
	fusermount -u $work/sysos
	rm -v "$SYSOS"
fi
ex=()
for e in $EXCLUDE; do ex+=(--exclude "$e/*"); done
copy "$(src os)" $R "${ex[@]}"
echo "$(date +%T) copied"
df -h $R | tail -1

# shared cache where dyld also looks: hard links, no extra space
dsc=private/preboot/Cryptexes/OS/System/Library/Caches/com.apple.dyld
mkdir -p $R/System/Library/Caches/com.apple.dyld
for f in $R/$dsc/*; do
	ln "$f" "$R/System/Library/Caches/com.apple.dyld/${f##*/}"
done

# cryptex files with no counterpart in the OS root, hard-linked to their root path
python3 - $R << 'EOF'
import os, sys
root = sys.argv[1]
linked = 0
for c in ('OS', 'App'):
    base = os.path.join(root, 'private/preboot/Cryptexes', c)
    for d, dirs, files in os.walk(base):
        rel_dir = os.path.relpath(d, base)
        if rel_dir == 'System/Library/Caches/com.apple.dyld':
            continue
        for name in files + [n for n in dirs if os.path.islink(os.path.join(d, n))]:
            rel = os.path.normpath(os.path.join(rel_dir, name))
            dst = os.path.join(root, rel)
            if os.path.lexists(dst):
                continue
            src = os.path.join(d, name)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if os.path.islink(src):
                os.symlink(os.readlink(src), dst)	# Linux hfsplus cannot hard-link symlinks
                st = os.lstat(src)
                os.lchown(dst, st.st_uid, st.st_gid)
            else:
                os.link(src, dst)
            linked += 1
print(f'{linked} cryptex files linked into the root')
EOF

# logd's stores (owner _logd 272, modes, .migrated markers), normally made at restore
db=$R/private/var/db
install -d -o 272 -g 272 -m 0751 $db/diagnostics
install -d -o 272 -g 272 -m 0755 $db/uuidtext $db/diagnostics/timesync
for d in diagnostics uuidtext diagnostics/timesync; do
	install -o 272 -g 272 -m 0644 /dev/null $db/$d/.migrated
done

# darwin-vm's sysroot, signed, without replacing Apple's files (staged in the
# new volume itself: WSL's own disk is on D:, which this must not write to)
stage=$R/.sysroot-stage
rm -rf $stage && cp -a $SYSROOT $stage
: > "$OUT.hashes"
find $stage -type f | while read -r f; do
	if head -c 4 "$f" | od -An -tx1 | grep -q 'cf fa ed fe'; then
		python3 $S/adhoc_sign.py "$f" "com.asoft.$(basename "$f")" | cut -d' ' -f1 >> "$OUT.hashes"
	fi
done
rsync -rlptgo --ignore-existing $stage/ $R/	# not cp -a: no ACLs on Linux hfsplus
rm -rf $stage
echo "signed $(wc -l < "$OUT.hashes") sysroot binaries"

df -h $R | tail -1
sync
umount $R
fsck.hfsplus -f -y $NBD | grep -v 'Illegal name' || true
fsck.hfsplus -f -n $NBD | tail -3
echo "$(date +%T) done: $OUT"
