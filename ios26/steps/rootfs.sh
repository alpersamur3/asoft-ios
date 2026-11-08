disk_tools
[ -x $L/sysroot/bin/bash ] || SYSROOT_TAR=$A/downloads/ios_sysroot.tar.gz bash $S/sysroot-check.sh
fresh root26.qcow2 root26.qcow2.hashes
# (the helper VM has it as a disk, decrypted by ipsw.exe)
[ -s os/{SYSOS} ] || [ -b os/{SYSOS} ] || bash $S/sysos.sh
DROP_SYSOS=1 bash $S/mk-root26.sh
bash $S/m2-finish.sh $A/root26.qcow2
