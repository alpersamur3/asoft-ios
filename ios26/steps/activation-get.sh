disk_tools
overlay root26g.qcow2 root26-activation.qcow2
mkdir -p install/work
in_root root26-activation.qcow2 <<'EOF'
cp $R/usr/libexec/mobileactivationd $A/install/work/mobileactivationd.orig
ls -l $R/usr/libexec/mobileactivationd
EOF
