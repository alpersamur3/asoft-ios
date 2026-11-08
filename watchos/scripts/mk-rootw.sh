#!/bin/bash
# Build the partitioned watchOS 27.2 root disk for -M vresearch in place (no whole-disk copy first):
# mk-root26.sh's root (case-sensitive, journaled HFS+) on p1 and mk-root26g.sh's Data volume on p2,
# boot with rd=disk0s1. watchOS has no SystemOS/AppOS cryptex: the shared cache is in the OS image.
# darwin-vm's sysroot (bash, coreutils, ...) is retargeted to watchOS (platw.py) and ad-hoc signed,
# without overwriting Apple's files; its CDHashes go to $OUT.hashes. NanoTimeKit (faces) stays in.
# Run by Install-watchOS.ps1's rootfs step (WSL, as root, after disk_tools: nbd and hfsplus loaded).
# env: OS (the decrypted OS image), OUT (the qcow2 to make), S (the scripts), L (the Linux scratch:
#      $L/sysroot), NBD (a free nbd device), RSIZE, DSIZE, EXCLUDE
set -euo pipefail
OS=${OS:?decrypted OS image}
OUT=${OUT:?the qcow2 to make}
S=${S:?the scripts folder}
RSIZE=${RSIZE:-16G} DSIZE=${DSIZE:-8G}
NBD=${NBD:-/dev/nbd14}
SYSROOT=${SYSROOT:-${L:?}/sysroot}
EXCLUDE=${EXCLUDE:-/System/Library/LinguisticData /System/Library/PreinstalledAssetsV2 /usr/standalone}

case $NBD in /dev/nbd1[2-9]|/dev/nbd[2-9][0-9]) ;; *) echo "use /dev/nbd12 or higher"; exit 1;; esac
[[ ! -e $OUT ]] || { echo "refusing to overwrite $OUT"; exit 1; }
[[ ! -s /sys/block/${NBD#/dev/}/pid ]] || { echo "$NBD is in use"; exit 1; }

work=/tmp/mkrootw
mkdir -p $work/os $work/root $work/data
L1= L2=
cleanup() {
	for m in $work/data $work/root $work/os; do
		mountpoint -q "$m" && { umount "$m" 2> /dev/null || fusermount -u "$m" 2> /dev/null || true; }
	done
	for l in $L1 $L2; do losetup -d $l 2> /dev/null || true; done
	qemu-nbd -d $NBD > /dev/null 2>&1 || true
}
trap cleanup EXIT

ln -sfn "$OS" $work/os.dmg
apfs-fuse -o allow_other $work/os.dmg $work/os
SRC=$work/os; [ -d $work/os/root ] && SRC=$work/os/root

START=2048
P1=$(( $(numfmt --from=iec $RSIZE) / 512 )) P2=$(( $(numfmt --from=iec $DSIZE) / 512 ))
qemu-img create -q -f qcow2 "$OUT" $(( (START + P1 + P2 + 2048) * 512 ))
modprobe nbd max_part=0 2> /dev/null || true
grep -q hfsplus /proc/filesystems || modprobe hfsplus 2>/dev/null || insmod "${HFSPLUS_KO:?WSL has no hfsplus module: set HFSPLUS_KO}"
qemu-nbd -f qcow2 --cache=writeback -c $NBD "$OUT"
sleep 1
sgdisk -o -n 1:$START:+$P1 -t 1:AF00 -c 1:iOSRoot -n 2:$((START + P1)):+$P2 -t 2:AF00 -c 2:Data $NBD > /dev/null
L1=$(losetup -f --show -o $((START * 512)) --sizelimit $((P1 * 512)) $NBD)
L2=$(losetup -f --show -o $(( (START + P1) * 512 )) --sizelimit $((P2 * 512)) $NBD)
mkfs.hfsplus -s -J -v iOSRoot $L1 > /dev/null
mkfs.hfsplus -s -J -v Data $L2 > /dev/null
mount -t hfsplus -o force $L1 $work/root
R=$work/root

ex=(--exclude '/System/Library/Caches/com.apple.dyld/*.symbols')
for e in $EXCLUDE; do ex+=(--exclude "$e/*"); done
echo "$(date +%T) copying the OS root"
rsync -aH --numeric-ids "${ex[@]}" "$SRC/" "$R/" 2>&1 | grep -v 'No data available' || true
echo "$(date +%T) copied"
df -h $R | tail -1
# (rsync's errors are filtered above: a cut-off image shows here)
for f in sbin/launchd usr/lib/dyld System/Library/Caches/com.apple.dyld; do
	[ -e "$R/$f" ] || { echo "the OS image gave no /$f: is $OS whole? (decrypt it again)"; exit 1; }
done

# logd's stores (owner _logd 272, modes, .migrated markers), normally made at restore
db=$R/private/var/db
install -d -o 272 -g 272 -m 0751 $db/diagnostics
install -d -o 272 -g 272 -m 0755 $db/uuidtext $db/diagnostics/timesync
for d in diagnostics uuidtext diagnostics/timesync; do
	install -o 272 -g 272 -m 0644 /dev/null $db/$d/.migrated
done

# darwin-vm's sysroot, retargeted to watchOS and signed, without replacing Apple's files (its bash is
# the serial console's shell, which the installer's first boot talks to)
[ -x "$SYSROOT/bin/bash" ] || { echo "$SYSROOT has no bin/bash: the sysroot did not extract"; exit 1; }
stage=$R/.sysroot-stage
rm -rf $stage && cp -a $SYSROOT $stage
: > "$OUT.hashes"
find $stage -type f | while read -r f; do
	if head -c 4 "$f" | od -An -tx1 | grep -q 'cf fa ed fe'; then
		python3 -I $S/platw.py "$f" > /dev/null
		python3 $S/adhoc_sign.py "$f" "com.asoft.$(basename "$f")" | cut -d' ' -f1 >> "$OUT.hashes"
	fi
done
rsync -rlptgo --ignore-existing $stage/ $R/
rm -rf $stage
echo "signed $(wc -l < "$OUT.hashes") sysroot binaries"
[ -s "$OUT.hashes" ] && [ -x "$R/bin/bash" ] || { echo "no signed sysroot on the root (no /bin/bash)"; exit 1; }

# Data volume (p2) = the root's private/var, as mk-root26g.sh; the root gets its fstab
mount -t hfsplus -o force $L2 $work/data
rsync -aH --numeric-ids $R/private/var/ $work/data/ 2>&1 | grep -v 'No data available' || true
chown 0:0 $work/data; chmod 755 $work/data
printf '/dev/disk0s1 / hfs ro 0 1\n/dev/disk0s2 /private/var hfs rw,nosuid,nodev 0 2\n' > $R/private/etc/fstab
du -sh $work/data
df -h $R | tail -1
sync
umount $work/data $R
fsck.hfsplus -f -y $L1 | grep -v 'Illegal name' | tail -2 || true
fsck.hfsplus -f -n $L1 | tail -1
fsck.hfsplus -f -n $L2 | tail -1
echo "$(date +%T) done: $OUT"
