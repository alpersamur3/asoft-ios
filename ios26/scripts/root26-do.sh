#!/bin/bash
# Run a command on the iOS 26 root disk mounted read-write (WSL, as root):
#   root26-do.sh QCOW2 'command using $R'
# On a partitioned disk (mk-root26g.sh) $R is p1 with p2 (Data) mounted on
# $R/private/var, as the guest sees it.
# The guest must be shut down. Linux's hfsplus ignores the journal, so a volume
# iOS left with journal transactions gets them replayed by fsck.hfsplus first.
# env: NBD (default /dev/nbd12)
set -eu
IMG=$1
NBD=${NBD:-/dev/nbd12}
R=/tmp/r26		# mount point only
case $NBD in /dev/nbd1[2-9]|/dev/nbd[2-9][0-9]) ;; *) echo "use /dev/nbd12 or higher"; exit 1;; esac
[[ ! -s /sys/block/${NBD#/dev/}/pid ]] || { echo "$NBD is in use"; exit 1; }
modprobe nbd max_part=0 2> /dev/null || true
grep -q hfsplus /proc/filesystems || modprobe hfsplus 2>/dev/null || insmod "${HFSPLUS_KO:?WSL has no hfsplus module: build it and set HFSPLUS_KO}"
qemu-nbd -f qcow2 --cache=writeback -c $NBD "$IMG"
LOOPS=
cleanup() {
	mountpoint -q $R/private/var && umount $R/private/var
	mountpoint -q $R && umount $R
	for l in $LOOPS; do losetup -d $l; done
	qemu-nbd -d $NBD > /dev/null
}
trap cleanup EXIT
sleep 1
# partition N of the disk as a loop device, or the whole disk without a GPT
part() {
	local f
	f=$(sgdisk -i $1 $NBD 2> /dev/null | awk '/^First sector:/{f=$3} /^Last sector:/{print f, $3}')
	[ -n "$f" ] || { echo $NBD; return; }
	set -- $f
	losetup -f --show -o $(($1 * 512)) --sizelimit $(( ($2 - $1 + 1) * 512 )) $NBD
}
DEV=$(part 1)
[ $DEV = $NBD ] || LOOPS=$DEV
fsck.hfsplus -f -y $DEV | tail -2 || true
mkdir -p $R
mount -t hfsplus -o force $DEV $R
if [ $DEV != $NBD ]; then
	DATA=$(part 2)
	LOOPS="$DATA $LOOPS"
	fsck.hfsplus -f -y $DATA | tail -1 || true
	mount -t hfsplus -o force $DATA $R/private/var
fi
export R
bash -c "$2"
sync
