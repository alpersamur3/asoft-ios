# What visionOS's Linux steps need beyond the iOS 26 base's tools (ios26/installer/wsl-setup.sh): fusepy and
# libfuse2 (aearemote.py serves Apple's encrypted OS image to apfs-fuse over HTTP), Python's cryptography (AEA's
# AES-CTR), liblzfse (AEA segments), python3-venv (usd-core for the rooms' acoustic strip). apt only what is missing.
need=()
for p in python3-fusepy libfuse2t64 python3-cryptography liblzfse1 python3-venv; do
	dpkg -s $p > /dev/null 2>&1 || need+=($p)
done
if [ ${#need[@]} -gt 0 ]; then
	echo "apt: ${need[*]}"
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq "${need[@]}" > /dev/null
fi
grep -q '^user_allow_other' /etc/fuse.conf 2> /dev/null || echo user_allow_other >> /etc/fuse.conf
python3 -I -c 'import cryptography, fusepy, ctypes.util; assert ctypes.util.find_library("lzfse"), "no liblzfse"' ||
	{ echo "the Python modules or liblzfse are still missing (see above)"; exit 1; }
for t in ipsw apfs-fuse qemu-nbd qemu-img sgdisk mkfs.hfsplus fusermount curl rsync; do
	command -v $t > /dev/null || { echo "no $t in the WSL distro: ios26\\Install-iOS26.cmd -Only linux sets the base's tools up"; exit 1; }
done
echo "tools ok"
