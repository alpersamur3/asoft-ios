#!/bin/bash
# Helper job build-root: the iOS root disk, ready to boot, from an IPSW.
#
# Disks, by virtio serial: ipsw (the .ipsw file itself, read-only), root (the disk to
# build, 16 GiB), scratch (room for the images the zip deflated, 3 GiB for 20H392).
# An image stored in the zip is read in place through a loop device over its bytes;
# a deflated one is inflated into scratch (a small one into RAM). Then the same steps
# as on Linux: tools/mkiosroot.sh, tools/sweet-root-tweaks.py, asoftinstalld
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
declare -A off size stored
while read -r role o s st _; do
    off[$role]=$o size[$role]=$s stored[$role]=$st
done < <(python3 ipsw-members.py "$ipsw")

scratch_used=0
image() {    # image ROLE: sets $path to something holding that image's bytes
    local role=$1
    if [ "${stored[$role]}" = 1 ]; then
        path=$(losetup -r -f --show -o "${off[$role]}" --sizelimit "${size[$role]}" "$ipsw")
    elif [ "${size[$role]}" -lt $((256 << 20)) ]; then
        path=/tmp/$role.dmg
        python3 ipsw-members.py "$ipsw" "$role" "$path"
    else
        progress 3 "unpacking $role ($((size[$role] >> 20)) MB)"
        path=$(losetup -f --show -o "$scratch_used" --sizelimit "${size[$role]}" "$scratch")
        python3 ipsw-members.py "$ipsw" "$role" "$path"
        scratch_used=$(( (scratch_used + size[$role] + (1 << 20) - 1) >> 20 << 20 ))
    fi
}
image OS;       os=$path
image SystemOS; sysos=$path
image AppOS;    appos=$path

# The copy is most of the time: report how far it is from the new volume's use
# (about 12.5 GB for 20H392)
(
    while sleep 30; do
        used=$(df -k 2>/dev/null | awk -v d="$root" '$1 == d { print $3 }')
        [ -n "$used" ] || continue
        pct=$((10 + used * 80 / (12500 * 1024)))
        progress $((pct > 90 ? 90 : pct)) "copying iOS ($((used >> 10)) MB)"
    done
) &
watcher=$!
progress 10 "copying iOS"
bash mkiosroot.sh "$os" "$sysos" "$appos" "$root"
kill $watcher 2>/dev/null || true

progress 92 "setting iOS up"
mkdir -p /mnt/root
mount -t hfsplus -o force "$root" /mnt/root
python3 sweet-root-tweaks.py /mnt/root
if [ -f asoftinstalld ]; then
    bash asoft-disk.sh installer /mnt/root asoftinstalld
fi
bash asoft-disk.sh name /mnt/root "ASoftware iPhone"
sync
umount /mnt/root
fsck.hfsplus -f -n "$root"
progress 100 "iOS disk ready"
