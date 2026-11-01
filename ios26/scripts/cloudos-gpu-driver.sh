#!/bin/bash
# cloudos-gpu-driver.sh AEA OUTDIR [TRUSTCACHE]
#
# Apple's guest GPU driver (AppleParavirtGPUMetalIOGPUFamily.bundle) out of a cloudOS (Private
# Cloud Compute) OS image, without a Mac and without a restore. Run as root in WSL (ios-emu);
# Install-iOS26.ps1's gpu step runs it (GpuMode cloudos).
#
#   AEA         the IPSW's "OS" member, e.g. cloudos/094-39278-029.dmg.aea of cloudOS 26.4b
#               (23E5207q, 754974720 bytes; ipsw-get.py fetches it by HTTP ranges)
#   OUTDIR      gets AppleParavirtGPUMetalIOGPUFamily.bundle: Apple's three files (binary,
#               Info.plist, _CodeSignature/CodeResources). cloudOS has no compiler plugin
#               (libAppleParavirtCompilerPluginIOGPUFamily.dylib): that one is not Apple's.
#   TRUSTCACHE  optional: Firmware/<AEA>.trustcache of the same IPSW; the binary's CDHash must
#               be in it (Apple's own list for that image: proves the file is unmodified)
#
# The key: every cloudOS OS image checked (26.1 23B83 .. 26.7 23H20) carries its AEA key in its
# own header, the auth-data field "encryption_key" (hex). `ipsw fw aea` uses that field before
# anything else (pkg/aea/decrypt.go), so Apple's key server is not asked. (Its fcs-key URLs
# answer 403 for every cloudOS build since 2026-09; the iPhone images' still answer 200.)
#
# Needs: ipsw (blacktop, 3.1.739 tested), apfs-fuse. Space next to AEA: the decrypted image
# (1.4 GB for 23E5207q), deleted at the end. Time here: decrypt 9 s, the rest seconds.
set -euo pipefail
AEA=$(realpath "${1:?usage: cloudos-gpu-driver.sh AEA OUTDIR [TRUSTCACHE]}")
OUT=${2:?usage: cloudos-gpu-driver.sh AEA OUTDIR [TRUSTCACHE]}
TC=${3:-}
NAME=AppleParavirtGPUMetalIOGPUFamily
B=System/Library/Extensions/$NAME.bundle
[ ! -e "$OUT/$NAME.bundle" ] || { echo "$OUT/$NAME.bundle exists" >&2; exit 1; }
command -v ipsw apfs-fuse > /dev/null

WORK=$(mktemp -d "$(dirname "$AEA")/gpu-driver.XXXXXX")
MNT=$(mktemp -d /tmp/gpu-driver-mnt.XXXXXX)
cleanup() {
	mountpoint -q "$MNT" && { fusermount -u "$MNT" 2> /dev/null || umount "$MNT"; }
	rmdir "$MNT" 2> /dev/null || true
	rm -rf "${WORK:?}"
}
trap cleanup EXIT

# no grep -q in these pipes: it quits at the first match, the writer gets SIGPIPE, and pipefail
# turns that into a failure
ipsw fw aea --info "$AEA" 2>&1 | grep '^\[encryption_key\]' > /dev/null \
	|| echo "warning: no encryption_key in the AEA header: ipsw will ask Apple's key server" >&2
ipsw fw aea "$AEA" -o "$WORK" | tail -1
IMG=$(find "$WORK" -maxdepth 1 -type f | head -1)
head -c 64 "$IMG" | grep NXSB > /dev/null || { echo "the decrypted image is not APFS" >&2; exit 1; }

apfs-fuse -o ro "$IMG" "$MNT"
ROOT=$MNT/root
[ -d "$ROOT" ] || ROOT=$MNT
[ -f "$ROOT/$B/$NAME" ] || { echo "no $B in this image" >&2; exit 1; }
grep -A1 -E 'ProductVersion|ProductBuildVersion' "$ROOT/System/Library/CoreServices/SystemVersion.plist" \
	| grep -o '<string>[^<]*' | sed 's/<string>/image: /'
mkdir -p "$OUT"
cp -R "$ROOT/$B" "$OUT/"

CD=$(ipsw macho info -s --no-color "$OUT/$NAME.bundle/$NAME" | awk '/CDHash:/ {print substr($2, 1, 40)}')
echo "CDHash $CD"
[ ${#CD} -eq 40 ] || { echo "no CDHash for $NAME" >&2; exit 1; }
if [ -n "$TC" ]; then
	if od -An -v -tx1 "$TC" | tr -d ' \n' | grep "$CD" > /dev/null; then
		echo "the CDHash is in $(basename "$TC")"
	else
		echo "the CDHash is NOT in $(basename "$TC")" >&2
		exit 1
	fi
fi
find "$OUT/$NAME.bundle" -type f -exec sha1sum {} +
