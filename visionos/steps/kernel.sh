rm -rf "$W/build/kc"; mkdir -p "$W/build/kc"
ipsw kernel dec "$A/{PACKED}" -o "$W/build/kc" 2>&1 | tail -1
set -- "$W"/build/kc/kernelcache.research.vphone600*decompressed
[ -f "$1" ] || { echo "ipsw kernel dec made no kernel out of {PACKED}"; exit 1; }
mv "$1" "$W/build/kc/kernel"
ls -l "$W/build/kc/kernel"
