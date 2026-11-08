disk_tools
overlay root26-apps.qcow2 root26-gpu.qcow2
in_root root26-gpu.qcow2 <<'EOF'
B=${R:?}/System/Library/Extensions/{BUNDLE}
rm -rf "${B:?}"
cp -R $A/install/work/gpu/{BUNDLE} "$B"
chown -R 0:0 "$B"
find "$B" -type d -exec chmod 755 {} +
find "$B" -type f -exec chmod 644 {} +
ls -l "$B" "$B"/*
EOF
