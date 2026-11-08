disk_tools
[ -x $L/sysroot/bin/bash ] || SYSROOT_TAR=$A/downloads/ios_sysroot.tar.gz bash $S/sysroot-check.sh
[ -x $L/sysroot/bin/bash ] || { echo "the sysroot did not extract into $L/sysroot (see above)"; exit 1; }
# (in the helper VM rootw.qcow2 is the new disk QEMU opened, linked here: it stays)
[ -b "$W/rootw.qcow2" ] || rm -f "$W/rootw.qcow2"
rm -f "$W/rootw.qcow2.hashes"
OS=$W/os/{OS} OUT=$W/rootw.qcow2 bash $S/mk-rootw.sh
