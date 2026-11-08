disk_tools
rm -rf "$W/build/dscpatch" "$W/rootw-p.hashes"
overlay rootw.qcow2 watchos/rootw-p.qcow2
in_root watchos/rootw-p.qcow2 <<'EOF'
P=$W/build/dscpatch
. $S/rootw-patch.sh
B=$R/System/Library/Extensions/{BUNDLE}
rm -rf "${B:?}"
cp -R "$W/gpu/{BUNDLE}" "$B"
chown -R 0:0 "$B"
find "$B" -type d -exec chmod 755 {} +
find "$B" -type f -exec chmod 644 {} +
ls -l "$B"
EOF
# the patched subcaches' CDHashes for the trust cache, kept beside the layer they are on
cp "$W/build/dscpatch/hashes.txt" "$W/rootw-p.hashes"
