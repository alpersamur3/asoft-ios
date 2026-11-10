# What a stopped rootfs or rooms step may leave in WSL: the remote image's FUSE mounts (and the Python process
# that serves one, which ends with its mount), and the usd-core venv (the rooms step makes it again).
for m in $L/vis/os $L/vis/aea /tmp/asoft-rt.*; do
	mountpoint -q "$m" 2> /dev/null && { fusermount -u "$m" 2> /dev/null || umount -l "$m"; echo "unmounted $m"; }
done
rmdir $L/vis/os $L/vis/aea $L/vis /tmp/asoft-rt.* 2> /dev/null || true
[ -n '{KEEP}' ] || rm -rf "${L:?}/usdenv"
true
