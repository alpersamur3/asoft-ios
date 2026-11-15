# The root disk, tvos/roott.qcow2 (p1 the root, p2 the Data volume), from the unpacked root (the unpack step's ext4
# image, mounted read only here) with mk-roott.sh; the signed sysroot's CDHashes to roott.qcow2.hashes.
disk_tools
[ -x $L/sysroot/bin/bash ] || SYSROOT_TAR=$A/downloads/ios_sysroot.tar.gz bash $S/sysroot-check.sh
[ -x $L/sysroot/bin/bash ] || { echo "the sysroot did not extract into $L/sysroot (see above)"; exit 1; }
I=$W/build/root.ext4
[ -s "$I" ] && [ -e "$I.ok" ] || { echo "no whole unpacked root ($I): the unpack step makes it"; exit 1; }
rm -f "$W/roott.qcow2" "$W/roott.qcow2.hashes"
M=$L/tv/root
mkdir -p $M "$W/build"
tv_umount() { mountpoint -q $M && { umount $M || umount -l $M; }; true; }
tv_umount
trap tv_umount EXIT
mount -o loop,ro "$I" $M
python3 -I -c 'import plistlib, sys; d = plistlib.load(open(sys.argv[1], "rb")); print(d["ProductName"], d["ProductVersion"], d["ProductBuildVersion"]); sys.exit(d["ProductBuildVersion"] != "24K122")' \
	$M/System/Library/CoreServices/SystemVersion.plist || { echo "the unpacked root is not tvOS 27.2 (24K122)"; exit 1; }
SRC=$M OUT=$W/roott.qcow2 ERRLOG=$W/build/rsync-root.txt bash $S/mk-roott.sh
