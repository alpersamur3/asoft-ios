#!/bin/bash
# Decompress the vphone600 kernelcaches and list their kexts.
set -e
A=${ASOFT26:?set ASOFT26 to the build folder as WSL sees it, e.g. /mnt/d/ios26}
cd "$A"
mkdir -p cloud
for k in research release; do
	# (Install-iOS26.ps1 -Base does not fetch the release kernel: only its kexts list needs it)
	if [ "$k" = release ] && [ ! -f cloudos/kernelcache.$k.vphone600 ]; then echo "no cloudos/kernelcache.$k.vphone600: skipped"; continue; fi
	ipsw kernel dec cloudos/kernelcache.$k.vphone600 -o cloud 2>&1 | tail -1
	f=$(ls cloud/kernelcache.$k.vphone600*decompressed 2>/dev/null | head -1)
	ipsw kernel kexts "$f" > cloud/kexts.$k.txt 2>&1 || true
	wc -l cloud/kexts.$k.txt
done
ls -l cloud
ipsw macho info cloud/kernelcache.research.vphone600*decompressed 2>&1 | head -40
