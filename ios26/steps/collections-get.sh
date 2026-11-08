disk_tools
overlay root.qcow2 root-collections.qcow2
fresh dsc-wp dscpatch-wp
mkdir -p dsc-wp
in_root root-collections.qcow2 <<'EOF'
cp $R/System/Cryptexes/OS/System/Library/Caches/com.apple.dyld/{N} $A/dsc-wp/
EOF
