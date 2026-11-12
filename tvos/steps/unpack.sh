# The OS root out of the OTA's payloadv2: pbzm/LZRAVEN chunks of one Apple Archive stream, decoded by pbzm_dec
# (the lzraven step's) and unpacked by tvx.py into an ext4 image on the work drive (case-sensitive, owners, hard
# links, symlinks; the installer made the file sparse before this). Then the tree is checked: tvx.py's report (every
# path of the fixup manifest there), SystemVersion.plist (24K122), and vsig.py, every code page of every Mach-O and
# shared cache file against its signature and the CDHashes against the OS trust cache (measured on the hand-built
# tree: no bad page, 1554 of 1562 signed files in the trust cache, the other 8 kexts whose code is in the kernel).
# The image is marked whole (root.ext4.ok) only after that.
I=$W/build/root.ext4
F=$W/build/dec/ota.aa
META=$W/build/root-meta
M=$L/tv/root
[ -f "$I" ] || { echo "no $I (the installer makes it before this)"; exit 1; }
[ -s "$F" ] && [ -e "$W/build/dec.ok" ] && [ -s "$W/build/outer.json" ] || { echo "no decrypted OTA: the decrypt step makes it"; exit 1; }
[ -x "$L/liblzraven/pbzm_dec" ] || { echo "no $L/liblzraven/pbzm_dec: the lzraven step builds it"; exit 1; }
rm -f "$I.ok"
mkdir -p $M
tv_umount() { mountpoint -q $M && { umount $M || umount -l $M; }; true; }
tv_umount
# WSL's page cache grows with every byte written through it and is not given back to Windows by itself: dropped
# every 30 s while the 13 GB go through (the hand build did the same)
dropper=
stop() { [ -n "$dropper" ] && kill $dropper 2> /dev/null; tv_umount; }
trap stop EXIT
( while :; do sync; echo 1 > /proc/sys/vm/drop_caches; sleep 30; done ) &
dropper=$!
mkfs.ext4 -q -F -O ^has_journal -E lazy_itable_init=1,lazy_journal_init=1 -m 0 -L tvos272root "$I"
mount -o loop,noatime "$I" $M
rmdir $M/lost+found 2> /dev/null || true
rm -rf "$META"
PBZM_DEC=$L/liblzraven/pbzm_dec python3 -I $S/tvx.py "$F" "$W/build/outer.json" $M "$META"
python3 -I - "$META/report.json" "$M/System/Library/CoreServices/SystemVersion.plist" <<'EOF'
import json, plistlib, sys
r = json.load(open(sys.argv[1]))
if r['n_missing_files'] or r['n_missing_dirs']:
    sys.exit(f"the unpacked root lacks {r['n_missing_files']} files and {r['n_missing_dirs']} folders of the fixup manifest "
             f"(first: {(r['missing_files'] + r['missing_dirs'])[:3]})")
v = plistlib.load(open(sys.argv[2], 'rb'))
if v.get('ProductBuildVersion') != '24K122':
    sys.exit(f"the unpacked root is {v.get('ProductName')} {v.get('ProductBuildVersion')}, not 24K122")
print(f"{v['ProductName']} {v['ProductVersion']} ({v['ProductBuildVersion']}): {r['pass1'].get('file', 0)} files, "
      f"{r['pass1'].get('dir', 0)} folders, {r['hardlinks']} hard links, {r['symlinks']} symlinks")
EOF
echo "$(date +%T) checking the code signatures (vsig.py)"
python3 -I $S/vsig.py $M "$W/ota/{TC}" $S "$META/vsig.json"
python3 -I - "$META/vsig.json" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1]))
bad = r['bad_pages'] + r.get('malformed', [])
if bad:
    sys.exit(f'{len(bad)} files whose code does not match their signature, first {bad[:3]}')
if len(r['not_in_tc']) > {NOTINTC}:
    sys.exit(f"{len(r['not_in_tc'])} signed files not in the OS trust cache (measured: {NOTINTC}), first {r['not_in_tc'][:5]}")
print(f"signatures: {r['macho']} Mach-O and {r['dsc']} shared cache files, every page matches; "
      f"{r['in_tc']} in the OS trust cache, {len(r['not_in_tc'])} not (kexts)")
EOF
sync
tv_umount
: > "$I.ok"
df -h "$I" | tail -1
du -h "$I"
