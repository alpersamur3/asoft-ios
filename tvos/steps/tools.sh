# What tvOS's Linux steps need beyond the iOS 26 base's tools (ios26/installer/wsl-setup.sh): git, a C compiler
# and make (liblzraven and pbzm_dec are built from source in the lzraven step), e2fsprogs (the unpacked root's
# ext4 image). apt only what is missing.
need=()
for p in git gcc make libc6-dev e2fsprogs; do
	dpkg -s $p > /dev/null 2>&1 || need+=($p)
done
if [ ${#need[@]} -gt 0 ]; then
	echo "apt: ${need[*]}"
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq "${need[@]}" > /dev/null
fi
for t in ipsw qemu-nbd qemu-img sgdisk mkfs.hfsplus fsck.hfsplus mkfs.ext4 losetup rsync git cc make python3; do
	command -v $t > /dev/null || { echo "no $t in the WSL distro: ios26\\Install-iOS26.cmd -Only linux sets the base's tools up"; exit 1; }
done
# ipsw reads the OTA (fw aea, ota extract): its version, for the log
ipsw version 2> /dev/null | head -1 || true
echo "tools ok"
