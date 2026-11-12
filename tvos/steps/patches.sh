# The changes before the first boot (roott-patch.sh: tweaks, jobs, keybag, shared-cache patches, GPU driver,
# prefs) on an overlay made anew each time (roott.qcow2 stays as mk-roott.sh built it), so this step can be redone:
# the shared-cache patches find their stock bytes only once.
disk_tools
rm -rf "$W/build/dscpatch" "$W/roott-p.hashes"
overlay roott.qcow2 tvos/roott-p.qcow2
in_root tvos/roott-p.qcow2 <<'EOF'
P=$W/build/dscpatch GPU=$W/gpu
. $S/roott-patch.sh
EOF
# the patched subcaches' CDHashes for the trust cache, kept beside the layer they are on
cp "$W/build/dscpatch/hashes.txt" "$W/roott-p.hashes"
