#!/bin/bash
# Helper job build-root: the iOS root disk, ready to boot, from an IPSW.
#
# Disks, by virtio serial: ipsw (the .ipsw file itself, read-only), root (the disk to
# build, 16 GiB), scratch (room for the three disk images, 7.5 GB for 20H392). The
# images are unpacked from the zip into files on scratch: apfs-fuse reads a UDIF
# image's trailer from the last 512 bytes of the file, and a loop device over the
# image's bytes inside the zip cannot end in the middle of a sector. Then the same
# steps as on Linux: tools/mkiosroot.sh, tools/sweet-root-tweaks.py, asoftinstalld
# (tools/asoft-disk.sh installer) and the device name.
set -euo pipefail
cd /asoft

progress() { echo "ASOFT: progress $*"; }
disk() {
    local d
    for d in /sys/block/vd*; do
        if [ "$(cat "$d/serial" 2>/dev/null)" = "$1" ]; then echo "/dev/${d##*/}"; return; fi
    done
    echo "ASOFT: no disk with serial $1" >&2
    exit 1
}
ipsw=$(disk ipsw) root=$(disk root) scratch=$(disk scratch)

progress 1 "reading the IPSW"
declare -A size offset stored
while read -r role o s st _; do
    size[$role]=$s offset[$role]=$o stored[$role]=$st
done < <(python3 ipsw-members.py "$ipsw")

# no journal: nothing on scratch outlives this job
mkfs.ext4 -q -F -O ^has_journal "$scratch"
mkdir -p /mnt/scratch
mount "$scratch" /mnt/scratch
image() {    # image ROLE: unpack it to /mnt/scratch/ROLE.dmg
    if [ "${stored[$1]}" = 1 ]; then
        # stored, as Apple's are: its bytes as they are, no CRC pass in Python
        dd if="$ipsw" of="/mnt/scratch/$1.dmg" bs=4M iflag=skip_bytes,count_bytes \
            skip="${offset[$1]}" count="${size[$1]}" status=none
    else
        python3 ipsw-members.py "$ipsw" "$1" "/mnt/scratch/$1.dmg"
    fi
}
progress 2 "unpacking the iOS images ($(( (size[OS] + size[SystemOS] + size[AppOS]) >> 20 )) MB)"
image OS & image SystemOS & image AppOS & wait
for role in OS SystemOS AppOS; do
    [ "$(stat -c %s "/mnt/scratch/$role.dmg")" = "${size[$role]}" ] || { echo "ASOFT: $role image short" >&2; exit 1; }
done
os=/mnt/scratch/OS.dmg sysos=/mnt/scratch/SystemOS.dmg appos=/mnt/scratch/AppOS.dmg

# The copy is most of the time: report how far it is from the new volume's use
# (about 12.5 GB for 20H392)
(
    while sleep 30; do
        used=$(df -k --output=source,used 2>/dev/null | sed -n "s#^$root  *##p")
        [ -n "$used" ] || continue
        pct=$((10 + used * 80 / (12500 * 1024)))
        progress $((pct > 90 ? 90 : pct)) "copying iOS ($((used >> 10)) MB)"
    done
) &
watcher=$!
progress 10 "copying iOS"
bash mkiosroot.sh "$os" "$sysos" "$appos" "$root"
kill $watcher 2>/dev/null || true
umount /mnt/scratch

progress 92 "setting iOS up"
mkdir -p /mnt/root
mount -t hfsplus -o force "$root" /mnt/root
python3 sweet-root-tweaks.py /mnt/root
if [ -f asoftinstalld ]; then
    bash asoft-disk.sh installer /mnt/root asoftinstalld
fi
# the device name is a nicety: a disk without it still boots
bash asoft-disk.sh name /mnt/root "ASoftware iPhone" || echo "ASOFT: warning: device name not set"
sync
umount /mnt/root
# Linux's hfsplus writes past the journal; let fsck_hfs settle the volume
fsck.hfsplus -f -y "$root" | tail -2 || true
progress 100 "iOS disk ready"
