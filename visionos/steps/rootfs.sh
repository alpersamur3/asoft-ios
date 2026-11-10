disk_tools
[ -x $L/sysroot/bin/bash ] || SYSROOT_TAR=$A/downloads/ios_sysroot.tar.gz bash $S/sysroot-check.sh
[ -x $L/sysroot/bin/bash ] || { echo "the sysroot did not extract into $L/sysroot (see above)"; exit 1; }
[ -s "$W/ipsw/os.idx" ] || { echo "no visionos/ipsw/os.idx: the ipsw step makes it"; exit 1; }
rm -f "$W/rootv.qcow2" "$W/rootv.qcow2.hashes"
mkdir -p "$W/build"
# Apple's OS image as it is in the IPSW: aearemote.py serves its plaintext as a file over FUSE (HTTP ranges,
# AEA segments decrypted as they are read), apfs-fuse mounts that. Nothing of it is stored but what is copied.
V=$L/vis
mkdir -p $V/aea $V/os
os_umount() {
	mountpoint -q $V/os && { fusermount -u $V/os || umount -l $V/os; }
	mountpoint -q $V/aea && { fusermount -u $V/aea || umount -l $V/aea; }
	true
}
os_umount
trap os_umount EXIT
nohup python3 -I $S/aearemote.py fuse "$W/ipsw/os.idx" $V/aea {CACHE_MB} > $W/build/aeafs.log 2>&1 &
for i in $(seq 1 30); do [ -e $V/aea/os.dmg ] && break; sleep 1; done
[ -e $V/aea/os.dmg ] || { cat $W/build/aeafs.log; echo "aearemote.py's FUSE did not come up"; exit 1; }
apfs-fuse -o allow_other $V/aea/os.dmg $V/os
python3 -I -c 'import plistlib, sys; d = plistlib.load(open(sys.argv[1], "rb")); print(d["ProductName"], d["ProductVersion"], d["ProductBuildVersion"]); sys.exit(d["ProductBuildVersion"] != "24N120")' \
	$V/os/root/System/Library/CoreServices/SystemVersion.plist || { echo "the image is not visionOS 27.2 (24N120)"; exit 1; }
SRC=$V/os/root OUT=$W/rootv.qcow2 ERRLOG=$W/build/rsync-root.txt bash $S/mk-rootx.sh
tail -1 $W/build/aeafs.log
