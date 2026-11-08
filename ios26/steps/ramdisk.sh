disk_tools
SYSROOT_TAR=$A/downloads/ios_sysroot.tar.gz bash $S/sysroot-check.sh
mkdir -p $L/rd cloud
# (the helper VM has it as a disk already, unwrapped by ipsw.exe)
[ -b $L/rd/rd.apfs ] || ipsw img4 im4p extract cloudos/094-39914-031.dmg -o $L/rd/rd.apfs
cp cloudos/Firmware/094-39914-031.dmg.trustcache cloud/rd.trustcache.im4p
bash $S/mk-ramdisk.sh
cp $L/rd/rd-shell.hfs $A/rd-shell.hfs
rm -f "${L:?}/rd/rd.apfs"
ls -l $A/rd-shell.hfs
