#!/bin/bash
# Build the partitioned visionOS 27.2 (24N120, RealityDevice14,1) root disk for -M vresearch straight from the
# OS image as a mounted tree (the rootfs step mounts Apple's encrypted image over HTTP: no IPSW and no decrypted
# copy on disk). mk-rootw.sh's layout: case-sensitive journaled HFS+ root on p1 (rd=disk0s1), Data volume =
# private/var on p2. Trimmed (notes/VISIONOS.md section 4): no .symbols, LinguisticData, /usr/standalone,
# ANE model bundles (H14*), videos, Siri dialog catalogs, non-English .lproj. darwin-vm's sysroot is retargeted
# to visionOS (platx.py) and ad-hoc signed, without overwriting Apple's files; its CDHashes go to $OUT.hashes.
# Run by Install-visionOS.ps1's rootfs step (WSL, as root, after disk_tools: nbd and hfsplus loaded).
# env: SRC (the OS image's root, mounted), OUT (the qcow2 to make), S (the scripts), L (the Linux scratch:
#      $L/sysroot), NBD (a free nbd device), RSIZE, DSIZE, ERRLOG (rsync's error lines; default $OUT.rsync.txt)
set -euo pipefail
SRC=${SRC:?the mounted OS root}
OUT=${OUT:?the qcow2 to make}
S=${S:?the scripts folder}
RSIZE=${RSIZE:-20G} DSIZE=${DSIZE:-8G}
NBD=${NBD:-/dev/nbd14}
SYSROOT=${SYSROOT:-${L:?}/sysroot}
ERRLOG=${ERRLOG:-$OUT.rsync.txt}

[ -f "$SRC/System/Library/CoreServices/SystemVersion.plist" ] || { echo "no OS root at $SRC (the image is not mounted)"; exit 1; }
case $NBD in /dev/nbd1[2-9]|/dev/nbd[2-9][0-9]) ;; *) echo "use /dev/nbd12 or higher"; exit 1;; esac
[[ ! -e $OUT ]] || { echo "refusing to overwrite $OUT"; exit 1; }
[[ ! -s /sys/block/${NBD#/dev/}/pid ]] || { echo "$NBD is in use"; exit 1; }
[ -x "$SYSROOT/bin/bash" ] || { echo "$SYSROOT has no bin/bash: the sysroot did not extract"; exit 1; }

work=$(mktemp -d /tmp/mkrootx.XXXXXX)
mkdir -p $work/root $work/data
L1= L2=
cleanup() {
	for m in $work/data $work/root; do
		mountpoint -q "$m" && { umount "$m" 2> /dev/null || true; }
	done
	for l in $L1 $L2; do losetup -d $l 2> /dev/null || true; done
	qemu-nbd -d $NBD > /dev/null 2>&1 || true
	rmdir $work/data $work/root $work 2> /dev/null || true
}
trap cleanup EXIT

START=2048
P1=$(( $(numfmt --from=iec $RSIZE) / 512 )) P2=$(( $(numfmt --from=iec $DSIZE) / 512 ))
grep -q hfsplus /proc/filesystems || modprobe hfsplus 2>/dev/null || insmod "${HFSPLUS_KO:?WSL has no hfsplus module: set HFSPLUS_KO}"
qemu-img create -q -f qcow2 "$OUT" $(( (START + P1 + P2 + 2048) * 512 ))
modprobe nbd max_part=0 2> /dev/null || true
qemu-nbd -f qcow2 --cache=writeback -c $NBD "$OUT"
sleep 1
sgdisk -o -n 1:$START:+$P1 -t 1:AF00 -c 1:iOSRoot -n 2:$((START + P1)):+$P2 -t 2:AF00 -c 2:Data $NBD > /dev/null
L1=$(losetup -f --show -o $((START * 512)) --sizelimit $((P1 * 512)) $NBD)
L2=$(losetup -f --show -o $(( (START + P1) * 512 )) --sizelimit $((P2 * 512)) $NBD)
mkfs.hfsplus -s -J -v iOSRoot $L1 > /dev/null
mkfs.hfsplus -s -J -v Data $L2 > /dev/null
mount -t hfsplus -o force $L1 $work/root
R=$work/root

flt=(
	--exclude '/System/Library/Caches/com.apple.dyld/*.symbols'
	--exclude '/System/DriverKit/System/Library/dyld/*.symbols'
	--exclude '/System/Library/LinguisticData/*'
	--exclude '/usr/standalone/*'
	--exclude 'H14G*' --exclude 'H14.*' --exclude 'H14_*' --exclude 'h14/'
	--exclude '*.mov' --exclude '*.mp4' --exclude '*.m4v'
	--exclude '*.catfamily/' --exclude '*.cat.bin'
	--include 'en.lproj/' --include 'Base.lproj/' --include 'en_US.lproj/' --include 'English.lproj/' --exclude '*.lproj/'
)
# One rsync at a time: apfs-fuse gives EIO under parallel reads; --whole-file: no delta reads. A read the
# remote image could not answer (the network) is an error line: the pass is run again (rsync then copies only
# what is missing or differs), at most three times. "No data available" lines (xattrs hfsplus will not take)
# are not errors.
for pass in 1 2 3; do
	echo "$(date +%T) copying the OS root from the image (pass $pass)"
	rc=0
	rsync -aH --whole-file --numeric-ids "${flt[@]}" "$SRC/" "$R/" 2> "$ERRLOG" || rc=$?
	bad=$(grep -vc 'No data available' "$ERRLOG" || true)
	echo "$(date +%T) rsync exit $rc, $bad error line(s) ($ERRLOG)"
	[ "$bad" = 0 ] && break
	grep -v 'No data available' "$ERRLOG" | head -5
	[ $pass = 3 ] && { echo "the OS root did not copy whole in three passes"; exit 1; }
done
df -h $R | tail -1
for f in sbin/launchd usr/lib/dyld System/Library/Caches/com.apple.dyld Applications/RealityLauncher.app/RealityLauncher; do
	[ -e "$R/$f" ] || { echo "the OS image gave no /$f"; exit 1; }
done

# logd's stores (owner _logd 272, modes, .migrated markers), normally made at restore
db=$R/private/var/db
install -d -o 272 -g 272 -m 0751 $db/diagnostics
install -d -o 272 -g 272 -m 0755 $db/uuidtext $db/diagnostics/timesync
for d in diagnostics uuidtext diagnostics/timesync; do
	install -o 272 -g 272 -m 0644 /dev/null $db/$d/.migrated
done

# darwin-vm's sysroot, retargeted to visionOS and signed, without replacing Apple's files (its bash is the
# serial console's shell, which the installer's boots talk to)
stage=$R/.sysroot-stage
rm -rf $stage && cp -a $SYSROOT $stage
: > "$OUT.hashes"
find $stage -type f | sort | while read -r f; do
	if head -c 4 "$f" | od -An -tx1 | grep -q 'cf fa ed fe'; then
		python3 -I $S/platx.py "$f" > /dev/null
		python3 $S/adhoc_sign.py "$f" "com.asoft.$(basename "$f")" | cut -d' ' -f1 >> "$OUT.hashes"
	fi
done
rsync -rlptgo --ignore-existing $stage/ $R/
rm -rf $stage
echo "signed $(wc -l < "$OUT.hashes") sysroot binaries"
[ -s "$OUT.hashes" ] && [ -x "$R/bin/bash" ] || { echo "no signed sysroot on the root (no /bin/bash)"; exit 1; }

# Data volume (p2) = the root's private/var; the root gets its fstab
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
