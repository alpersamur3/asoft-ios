disk_tools
rm -rf "$W/build/patch" "$W/rootv-p.hashes"
overlay rootv.qcow2 visionos/rootv-p.qcow2
in_root visionos/rootv-p.qcow2 <<'EOF'
P=$W/build/patch GPU=$W/gpu ROOMS=$W/rooms NOAUDIO=$W/rooms-noaudio AUDIO='{AUDIO}'
. $S/rootx-patch.sh
EOF
# the patched binaries' CDHashes for the trust cache, kept beside the layer they are on
cp "$W/build/patch/hashes.txt" "$W/rootv-p.hashes"
