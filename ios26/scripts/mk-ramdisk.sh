#!/bin/bash
# Build an HFS+ (case-sensitive) ramdisk for -M vresearch, run in WSL as root:
#   Apple's cloudOS ramdisk tree (from the unwrapped APFS image, via apfs-fuse)
#   + darwin-vm's prebuilt iOS sysroot (bash, coreutils, ...), ad-hoc signed here
#   + a launchd plist that runs bash on the console instead of restored_external
# and a trust cache = Apple's ramdisk trust cache + our CDHashes.
#
#   mk-ramdisk.sh
# env: RD (APFS ramdisk), APPLE_TC, OUTDIR, NBD (default /dev/nbd12)
set -eu
A=${ASOFT26:?set ASOFT26 to the build folder as WSL sees it, e.g. /mnt/d/ios26}
L=${ASOFT26_LINUX:-/root/ios26}
S=$(cd "$(dirname "$0")" && pwd)
RD=${RD:-$L/rd/rd.apfs}
APPLE_TC=${APPLE_TC:-$A/cloud/rd.trustcache.im4p}
OUTDIR=${OUTDIR:-$L/rd}
NBD=${NBD:-/dev/nbd12}
IMG=$OUTDIR/rd-shell.hfs
SRC=/tmp/rdm
DST=/tmp/rdh
SYSROOT=$L/sysroot

case $NBD in /dev/nbd1[2-9]|/dev/nbd[2-9][0-9]) ;; *) echo "use /dev/nbd12 or higher"; exit 1;; esac

mkdir -p $SRC $DST
mountpoint -q $SRC || apfs-fuse -o allow_other "$RD" $SRC
cleanup() {
	mountpoint -q $DST && umount $DST
	qemu-nbd -d $NBD > /dev/null 2>&1 || true
	mountpoint -q $SRC && fusermount -u $SRC
}
trap cleanup EXIT

# size: the APFS tree uncompressed (apfs-fuse decompresses), without the
# device firmware in usr/standalone (861 MB), plus room
KB=$(( $(du -s --apparent-size --block-size=1K $SRC/root | cut -f1) - 	$(du -s --apparent-size --block-size=1K $SRC/root/usr/standalone | cut -f1) ))
MB=$(( KB / 1024 * 13 / 10 + 96 ))
echo "ramdisk tree ${KB} KB -> image ${MB} MB"
rm -f "$IMG"
truncate -s ${MB}M "$IMG"
mkfs.hfsplus -s -v ramdisk "$IMG" > /dev/null

modprobe nbd max_part=0 2> /dev/null || true
# the WSL kernel has no hfsplus; same module and check as the iOS 16 session's tools
grep -q hfsplus /proc/filesystems || modprobe hfsplus 2>/dev/null || insmod "${HFSPLUS_KO:?WSL has no hfsplus module: build it and set HFSPLUS_KO}"
qemu-nbd -f raw -c $NBD "$IMG"
sleep 1
mount -t hfsplus $NBD $DST

# Apple's tree (hard links, symlinks, owners, modes)
rsync -aH --numeric-ids --exclude /usr/standalone $SRC/root/ $DST/
mkdir -p $DST/usr/standalone

# the shell instead of the restore daemons
mv $DST/System/Library/LaunchDaemons $DST/System/Library/LaunchDaemons.apple
mkdir $DST/System/Library/LaunchDaemons
cat > $DST/System/Library/LaunchDaemons/com.asoft.bash.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.asoft.bash</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>-i</string>
	</array>
	<key>StandardInPath</key>
	<string>/dev/console</string>
	<key>StandardOutPath</key>
	<string>/dev/console</string>
	<key>StandardErrorPath</key>
	<string>/dev/console</string>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>KeepAlive</key>
	<true/>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
chmod 644 $DST/System/Library/LaunchDaemons/com.asoft.bash.plist

# sysroot: sign a copy, then add what Apple's tree doesn't have
rm -rf /tmp/sysroot-signed && cp -a $SYSROOT /tmp/sysroot-signed
: > $OUTDIR/rd-shell.hashes
find /tmp/sysroot-signed -type f | while read -r f; do
	if head -c 4 "$f" | od -An -tx1 | grep -q 'cf fa ed fe'; then
		python3 $S/adhoc_sign.py "$f" "com.asoft.$(basename "$f")" | cut -d' ' -f1 >> $OUTDIR/rd-shell.hashes
	fi
done
cp -a -n /tmp/sysroot-signed/. $DST/
chown -R 0:0 $DST/bin $DST/sbin $DST/libexec 2> /dev/null || true
echo "signed $(wc -l < $OUTDIR/rd-shell.hashes) binaries"
ls -la $DST/bin | head -5; ls -la $DST/bin/bash $DST/bin/sh
df -h $DST | tail -1

python3 $S/mktc.py $OUTDIR/rd-shell.tc "$APPLE_TC" $OUTDIR/rd-shell.hashes
sync
