# What a stopped unpack or rootfs step may leave in WSL: the unpacked root's loop mount, and a liblzraven fetch that
# did not finish (the finished build stays in $L/liblzraven: the lzraven step keeps a build of its commit). The
# installer removes the work drive's build files itself (the decrypted OTA, the unpacked root's image), unless
# -KeepBuildFiles.
M=$L/tv/root
if mountpoint -q $M 2> /dev/null; then
	umount $M 2> /dev/null || umount -l $M
	echo "unmounted $M"
fi
rmdir $M $L/tv 2> /dev/null || true
rm -rf "${L:?}/liblzraven.new"
true
