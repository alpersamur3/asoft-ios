# The OS image is read where it is, inside Apple's IPSW (aearemote.py: HTTP ranges, AEA decrypted segment by
# segment): its key from Apple's key service (ipsw fw aea --key, from the member's first MiB, which the installer
# fetched), then the index of its clusters (each cluster's HMAC checked against the key's chain).
I=$W/ipsw
ipsw fw aea --key "$I/os.aea.head" > "$I/os.key.new"
grep -q '^base64:' "$I/os.key.new" || { cat "$I/os.key.new"; echo "Apple's key service gave no key for {MEMBER}"; exit 1; }
mv "$I/os.key.new" "$I/os.key"
python3 -I $S/aearemote.py index '{URL}' {OFF} "$I/os.key" "$I/os.aea.head" "$I/os.idx.new"
python3 -I $S/aearemote.py read "$I/os.idx.new" 0 65536 "$I/os.first.bin"
# (an APFS container: its superblock NXSB at 32)
python3 -I -c 'import sys; b = open(sys.argv[1], "rb").read(); sys.exit(b[32:36] != b"NXSB")' "$I/os.first.bin" ||
	{ echo "the index's first bytes are no APFS container: the key or the index is wrong"; exit 1; }
rm -f "$I/os.first.bin"
mv "$I/os.idx.new" "$I/os.idx"
ls -l "$I/os.idx"
