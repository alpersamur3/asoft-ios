# The six synthetic rooms (LivingRoom/Kitchen/Museum, Day/Night) of Apple's visionOS 27.2 Simulator Runtime, the
# places Home shows behind its icons. The runtime is one 7.65 GB archive: AEA (its key from Apple's asset server,
# which the installer asked) -> Apple Archive -> pbzx -> Apple Archive -> a UDIF .dmg -> APFS; the two compression
# layers allow no random access, so the .dmg is streamed whole onto the work drive (never WSL's own disk), the
# rooms (266 MB) are copied off it and checked against their pinned SHA-256, and it goes.
# Then the rooms' usdc without their acoustic prims (usdacoustic.py with usd-core 26.11 in a venv).
B=$W/build/rooms
mkdir -p "$B"
cd "$B"
U='{URL}'
[ -s rt.key ] || { echo "no $B/rt.key (the installer writes it from Apple's answer)"; exit 1; }
[ -s rt.head ] || { curl -fsS --retry 5 -r 0-1048575 -o rt.head.new "$U" && mv rt.head.new rt.head; }
[ -s rt.idx ] || { python3 -I $S/aearemote.py index "$U" 0 rt.key rt.head rt.idx.new && mv rt.idx.new rt.idx; }
if [ ! -e rt.dmg.ok ]; then
	rm -f rt.dmg
	EDGE='{EDGE}' python3 -I $S/rtdmg.py "$B/rt.idx" "$B/rt.dmg"
	: > rt.dmg.ok
fi
M=$(mktemp -d /tmp/asoft-rt.XXXXXX)
rt_umount() { mountpoint -q $M && { fusermount -u $M || umount -l $M; }; rmdir $M 2> /dev/null || true; }
trap rt_umount EXIT
apfs-fuse -o allow_other "$B/rt.dmg" $M
RR="$M/root/Library/Developer/CoreSimulator/Profiles/Runtimes/xrOS 27.2.simruntime/Contents/Resources/RuntimeRoot"
SE="$RR/System/Library/Assets/SystemEnvironments/SyntheticEnvironments"
[ -d "$SE" ] || { ls "$M" "$M/root" 2>&1 | head; echo "no SyntheticEnvironments in the runtime image"; exit 1; }
N=$W/rooms.new
rm -rf "$N"; mkdir -p "$N"
cp -r "$SE/." "$N/"
rt_umount
trap - EXIT
(cd "$N" && sha256sum --quiet -c $S/rooms.sha256) || { echo "the rooms are not the pinned ones (rooms.sha256)"; exit 1; }
[ "$(find "$N" -type f | wc -l)" = "$(grep -c . $S/rooms.sha256)" ] || { echo "the rooms have files rooms.sha256 does not list"; exit 1; }
rm -rf "$W/rooms"; mv "$N" "$W/rooms"
echo "rooms: $(ls "$W/rooms" | tr '\n' ' ')($(du -sh "$W/rooms" | cut -f1))"

V=$L/usdenv
[ -x $V/bin/python ] || python3 -m venv $V
$V/bin/python -c 'from pxr import Usd' 2> /dev/null || $V/bin/pip install -q usd-core==26.11
N=$W/rooms-noaudio.new
rm -rf "$N"; mkdir -p "$N"
for d in "$W"/rooms/*/; do
	r=$(basename "$d")
	set -- "$d"AssetData/*.usdc
	[ $# = 1 ] && [ -f "$1" ] || { echo "$r: not one usdc in its AssetData"; exit 1; }
	mkdir -p "$N/$r"
	$V/bin/python -I $S/usdacoustic.py strip "$1" "$N/$r/$(basename "$1")"
done
(cd "$N" && sha256sum --quiet -c $S/rooms-noaudio.sha256) ||
	echo "(the stripped usdc differ from the ones measured with usd-core 26.11: another usd-core build; they are used as they are)"
rm -rf "$W/rooms-noaudio"; mv "$N" "$W/rooms-noaudio"
[ -n '{KEEP}' ] || { rm -f "$B/rt.dmg" "$B/rt.dmg.ok"; echo "removed the runtime's .dmg"; }
