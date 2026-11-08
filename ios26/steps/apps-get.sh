disk_tools
overlay root26-activation.qcow2 root26-apps.qcow2
fresh dsc dscpatch dscpatch-pb dscpatch-lp dscpatch-edge dscpatch-aod
mkdir -p dsc
in_root root26-apps.qcow2 <<'EOF'
bash $S/apply-staged.sh
C=$R/System/Cryptexes/OS/System/Library/Caches/com.apple.dyld
cp {DSC} $A/dsc/
EOF
ls -l dsc
