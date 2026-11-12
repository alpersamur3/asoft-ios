disk_tools
M=$(mktemp -d /tmp/asoft-gpu.XXXXXX) LP=
trap 'mountpoint -q $M && umount $M; [ -n "$LP" ] && losetup -d $LP; qemu-nbd -d $NBD > /dev/null' EXIT
qemu-nbd -r -f qcow2 -c $NBD "$A/{TOP}"; sleep 1
set -- $(sgdisk -i 1 $NBD | awk '/^First sector:/{f=$3} /^Last sector:/{print f, $3}')
LP=$(losetup -r -f --show -o $(($1 * 512)) --sizelimit $(( ($2 - $1 + 1) * 512 )) $NBD)
mount -t hfsplus -o ro $LP $M
B=System/Library/Extensions/{BUNDLE}
[ -d "$M/$B" ] || { echo "$B is not on {TOP} (a GPU-less iOS 26?)"; exit 1; }
N=$A/gpu-driver/.new
rm -rf "$N"; mkdir -p "$N"
cp -R "$M/$B" "$N/{BUNDLE}"
rm -rf "$A/gpu-driver/{BUNDLE}"
mv "$N/{BUNDLE}" "$A/gpu-driver/{BUNDLE}"
rmdir "$N"
ls -l "$A/gpu-driver/{BUNDLE}"
