# The OTA decrypted (AEA with the pinned key, as the hand build did: ipsw fw aea -b KEY), indexed (index_outer.py:
# the absolute offset of every payloadv2 member in the outer Apple Archive) and its boot files taken out (ipsw ota
# extract: the OS root's trust cache, J255's device tree, BuildManifest.plist). The decrypted archive goes to
# $W/build/dec (one file, 4.99 GB); the small files to $W/ota.
B=$W/build
mkdir -p "$B/tmp" "$W/ota"
export TMPDIR=$B/tmp
if [ ! -e "$B/dec.ok" ]; then
	rm -rf "$B/dec" "$B/outer.json"
	mkdir -p "$B/dec"
	ipsw fw aea -b '{KEY}' -o "$B/dec" '{AEA}' 2>&1 | tail -3
	set -- "$B"/dec/*
	[ $# = 1 ] && [ -f "$1" ] || { ls -la "$B/dec"; echo "ipsw fw aea did not leave one file in $B/dec"; exit 1; }
	[ "$(stat -c %s "$1")" = {DECSIZE} ] || { echo "$1 is $(stat -c %s "$1") bytes, not {DECSIZE} (another key or OTA?)"; exit 1; }
	[ "$(head -c 4 "$1")" = AA01 ] || { echo "$1 is no Apple Archive (AA01)"; exit 1; }
	[ "$1" = "$B/dec/ota.aa" ] || mv "$1" "$B/dec/ota.aa"
	: > "$B/dec.ok"
fi
F=$B/dec/ota.aa
# (its listing into a file, not "| head": under pipefail the writer's SIGPIPE would fail the step)
python3 -I $S/index_outer.py "$F" $S "$B/outer.json.new" > "$B/outer.txt"
sed -n 1p "$B/outer.txt"
python3 -I - "$B/outer.json.new" <<'EOF'
import json, sys
files = {f['pat'] for f in json.load(open(sys.argv[1]))['files']}
n = sum(1 for p in files if p and p.startswith('AssetData/payloadv2/payload.') and p[-3:].isdigit())
missing = [p for p in ('AssetData/payloadv2/fixup.manifest', 'AssetData/payloadv2/payload.000') if p not in files]
if missing or not n:
    sys.exit(f'the OTA index has no {missing or "payload chunks"}')
print(f'payloadv2: {n} chunks and the fixup manifest')
EOF
mv "$B/outer.json.new" "$B/outer.json"
X=$B/ota-boot
rm -rf "$X"; mkdir -p "$X"
ipsw ota extract "$F" --pattern '{PATTERN}' -o "$X" < /dev/null 2>&1 | tail -5
for n in {TC} DeviceTree.j255ap.im4p BuildManifest.plist; do
	f=$(find "$X" -type f -name "$n" | head -1 || true)
	[ -n "$f" ] || { find "$X" -type f | head; echo "ipsw ota extract gave no $n"; exit 1; }
	cp "$f" "$W/ota/$n.new" && mv "$W/ota/$n.new" "$W/ota/$n"
done
rm -rf "$X"
python3 -I - "$W/ota/BuildManifest.plist" "$W/ota/{TC}" $S <<'EOF'
import plistlib, sys
sys.path.insert(0, sys.argv[3])
from mktc import read_tc
m = plistlib.load(open(sys.argv[1], 'rb'))
if m.get('ProductBuildVersion') != '24K122' or 'AppleTV14,1' not in m.get('SupportedProductTypes', []):
    sys.exit(f"BuildManifest: {m.get('ProductBuildVersion')} {m.get('SupportedProductTypes')}, not 24K122 for AppleTV14,1")
n = len(read_tc(open(sys.argv[2], 'rb').read()))
if n != {TCENTRIES}:
    sys.exit(f'the OS trust cache has {n} entries, not {TCENTRIES}')
print(f"tvOS {m.get('ProductVersion')} ({m['ProductBuildVersion']}) for AppleTV14,1; OS trust cache {n} entries")
EOF
ls -l "$W/ota"
