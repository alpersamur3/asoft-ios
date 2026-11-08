disk_tools
in_root root26-activation.qcow2 <<'EOF'
cat $A/install/work/mobileactivationd > $R/usr/libexec/mobileactivationd
cmp $A/install/work/mobileactivationd $R/usr/libexec/mobileactivationd
ls -l $R/usr/libexec/mobileactivationd
EOF
