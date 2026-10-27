#!/bin/bash
# Partitioned iOS 26 disk from the whole-disk HFS+ root (mk-root26.sh), laid
# out like the phone: a read-only system volume and a separate rw Data volume
# for /private/var. The kernel refuses `mount -uw /` on the root, and two
# virtio-blk disks get their disk numbers in a different order each boot, so
# both volumes go on one disk:
#   p1 iOSRoot (copy of ROOT)    -> /dev/disk0s1, boot with rd=disk0s1
#   p2 Data (root's private/var) -> /dev/disk0s2 on /private/var
# Writes the new root's /etc/fstab. WSL, as root, guest shut down:
#   mk-root26g.sh ROOT.qcow2 OUT.qcow2 [DATA_SIZE]
# env: NBD, NBD2 (default /dev/nbd12, /dev/nbd13)
set -eu
ROOT=$1 OUT=$2 DSIZE=${3:-16G}
NBD=${NBD:-/dev/nbd12} NBD2=${NBD2:-/dev/nbd13}
R=/tmp/r26 D=/tmp/d26
for n in $NBD $NBD2; do
	case $n in /dev/nbd1[2-9]|/dev/nbd[2-9][0-9]) ;; *) echo "use /dev/nbd12 or higher"; exit 1;; esac
	[[ ! -s /sys/block/${n#/dev/}/pid ]] || { echo "$n is in use"; exit 1; }
done
[ -e "$OUT" ] && { echo "$OUT exists"; exit 1; }
modprobe nbd max_part=0 2> /dev/null || true
grep -q hfsplus /proc/filesystems || modprobe hfsplus 2>/dev/null || insmod "${HFSPLUS_KO:?WSL has no hfsplus module: build it and set HFSPLUS_KO}"
L1= L2=
cleanup() {
	for m in $D $R; do mountpoint -q $m && umount $m; done
	for l in $L1 $L2; do losetup -d $l; done
	qemu-nbd -d $NBD > /dev/null; qemu-nbd -d $NBD2 > /dev/null
}
trap cleanup EXIT
qemu-nbd -r -f qcow2 -c $NBD "$ROOT"
sleep 1
RBYTES=$(blockdev --getsize64 $NBD)
DBYTES=$(numfmt --from=iec $DSIZE)
START=2048					# sectors: p1 at 1 MiB
P1=$((RBYTES / 512)) P2=$((DBYTES / 512))
qemu-img create -q -f qcow2 "$OUT" $(( (START + P1 + P2 + 2048) * 512 ))
qemu-nbd -f qcow2 --cache=writeback -c $NBD2 "$OUT"
sleep 1
sgdisk -o -n 1:$START:+$P1 -t 1:AF00 -c 1:iOSRoot -n 2:$((START + P1)):+$P2 -t 2:AF00 -c 2:Data $NBD2 > /dev/null
echo "copying $((RBYTES >> 20)) MiB"
dd if=$NBD of=$NBD2 bs=4M seek=$((START * 512)) oflag=seek_bytes conv=sparse,notrunc status=none
L1=$(losetup -f --show -o $((START * 512)) --sizelimit $RBYTES $NBD2)
L2=$(losetup -f --show -o $(( (START + P1) * 512 )) --sizelimit $DBYTES $NBD2)
fsck.hfsplus -f -y $L1 | tail -1 || true
mkfs.hfsplus -s -J -v Data $L2 > /dev/null
mkdir -p $R $D
mount -t hfsplus -o force $L1 $R
mount -t hfsplus -o force $L2 $D
rsync -aH --numeric-ids $R/private/var/ $D/ 2>&1 | grep -v 'No data available' || true
chown 0:0 $D; chmod 755 $D
printf '/dev/disk0s1 / hfs ro 0 1\n/dev/disk0s2 /private/var hfs rw,nosuid,nodev 0 2\n' > $R/private/etc/fstab
du -sh $D
sync
