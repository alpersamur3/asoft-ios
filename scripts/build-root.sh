#!/bin/bash
# Build the iOS 16.7.16 root image for QEMU from the extracted IPSW disk images:
# tools/mkiosroot.sh (APFS -> one HFS+ volume) + tools/sweet-root-tweaks.py.
# Needs the hfsplus module (scripts/wsl-build-hfsplus.sh). Runs inside ios-emu:
#   wsl -d ios-emu -u root -- bash scripts/build-root.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
IPSW_DIR=/root/work/ipsw-20H392
OUT_DIR=/root/work/root
IMG=$OUT_DIR/ios16-root-20H392.img
SIZE=${SIZE:-16G}

grep -q hfsplus /proc/filesystems || modprobe hfsplus
mkdir -p "$OUT_DIR"
cd "$IPSW_DIR"
read -r OS SYSOS APPOS < <(awk '{print $2}' dmgs.txt | paste -sd' ')

if [ ! -e "$IMG" ]; then
  bash "$REPO/tools/mkiosroot.sh" "$OS" "$SYSOS" "$APPOS" "$IMG.tmp" "$SIZE"
  mv "$IMG.tmp" "$IMG"
fi

fsck.hfsplus -fy "$IMG" || true
mkdir -p /mnt/iosroot
mountpoint -q /mnt/iosroot && umount /mnt/iosroot
mount -t hfsplus -o loop,force "$IMG" /mnt/iosroot
python3 "$REPO/tools/sweet-root-tweaks.py" /mnt/iosroot
cat /mnt/iosroot/System/Library/CoreServices/SystemVersion.plist | grep -A1 ProductBuildVersion
df -h /mnt/iosroot
sync
umount /mnt/iosroot

ls -lsh "$IMG"
sha256sum "$IMG" | tee "$IMG.sha256"
