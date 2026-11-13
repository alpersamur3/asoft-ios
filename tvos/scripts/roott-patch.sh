# The tvOS root's changes before its first boot, sourced by Install-tvOS.ps1's patches step inside in_root
# ($R = the root, p1, with the Data volume p2 on $R/private/var; S = the scripts; P = where the patched
# shared-cache copies and their CDHashes go, P/hashes.txt for the trust cache; GPU = the tvOS copy of the GPU
# driver, the gpu step's). The hand-built tvOS's cmdT1.sh and cmdT4.sh with their paths made parameters (notes:
# TVOS.md):
#  - root26-tweaks.py: com.asoft.bash on the serial console, _PanicOnCrash renamed, containers
#  - roott-jobs.py: backboardd without _Conclave (PineBoard has none in 24K122)
#  - the system keybag, as ios26's tweaks step makes it
#  - libsystem_darwin's lockdown-mode block: absent in tvOS 27.2 (0 hits, checked: another build that has it
#    stops here, as it would need watchOS's patch)
#  - IOMobileFramebuffer force-kern: dscforce.py with tvOS 24K122's own symbol list (10 trampolines)
#  - libxpc _xpc_token_satisfies_lwcr derives matched from error_code (1 hit in subcache .01 on 24K122)
#  - QuartzCore's display-mode scale as on a real Apple TV (dsc-qcscale.py, subcache .03): a 1920x1080 mode at 1x,
#    a 3840x2160 one at 2x as before, so one disk runs at 1080p and at 4K (the device tree picks the mode)
#  - the paravirtual GPU driver (iOS 26's, retargeted to tvOS and signed by the gpu step)
#  - roott-prefs.py (setup done, screen saver and idle screen off, watchdogs off) and root26-prefs.py
#    (DataMigration not run; activation once mobileactivationd's container exists: the persona step runs it again)
set -euo pipefail
: "${R:?}" "${S:?}" "${P:?}" "${GPU:?}"
C=$R/System/Library/Caches/com.apple.dyld
mkdir -p "$P"
: > "$P/hashes.txt"

python3 -I $S/root26-tweaks.py $R
python3 -I $S/roott-jobs.py $R
install -d -m 0700 -o 0 -g 0 $R/private/var/keybags
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>' \
	> $R/private/var/keybags/systembag.kb
chown 0:0 $R/private/var/keybags/systembag.kb
chmod 0600 $R/private/var/keybags/systembag.kb

# dsc_hits NAME HEX: how many times HEX is in the cache (dscfind.py's listing kept as $P/NAME-find.txt)
dsc_hits() {
	python3 -I $S/dscfind.py $C "$2" 0x10 > "$P/$1-find.txt" || { echo "dscfind.py failed on $C" >&2; exit 1; }
	grep -c ' va ' "$P/$1-find.txt" || true
}
# dsc_put LISTING: the patched subcache LISTING's last line names (in $P) over the cache's, its CDHash kept
dsc_put() {
	local f
	f=$(tail -1 "$1" | awk '{print $1}')
	cat "$P/$f" > "$C/$f"
	cmp "$P/$f" "$C/$f"
	tail -1 "$1" | awk '{print $3}' >> "$P/hashes.txt"
	rm -f "${P:?}/$f"
	echo "patched $f"
}
n=$(dsc_hits lockdown 1f04003120010054e80740f91f0500f1e8179f1a)
[ "$n" = 0 ] || { cat "$P/lockdown-find.txt"; echo "lockdown pattern: $n hits, none on 24K122 (another tvOS build?)"; exit 1; }
python3 -I $S/dscforce.py $C $S/iomfb-syms.txt $P | tee $P/iomfb.txt
dsc_put $P/iomfb.txt
n=$(dsc_hits lwcr e8079f1a0800084a88010036)
[ "$n" = 1 ] || { cat "$P/lwcr-find.txt"; echo "lwcr pattern: $n hits, expected 1 (another tvOS build?)"; exit 1; }
va=$(awk '/ va /{print $NF}' "$P/lwcr-find.txt")
python3 -I $S/dsc-patch.py $C $va e8079f1a0800084a88010036 e0179f1a1f2003d51f2003d5 $P | tee $P/lwcr.txt
dsc_put $P/lwcr.txt
# (a root that has it already keeps its subcache; its CDHash goes into the trust cache all the same)
python3 -I $S/dsc-qcscale.py $C $P | tee $P/qcscale.txt
if [ "$(awk 'NR==1{print $4}' $P/qcscale.txt)" = already ]; then
	awk 'NR==1{print $3}' $P/qcscale.txt >> "$P/hashes.txt"
	echo "QuartzCore's display-mode scale patch was there already"
else
	dsc_put $P/qcscale.txt
fi

B=$R/System/Library/Extensions/AppleParavirtGPUMetalIOGPUFamily.bundle
rm -rf "${B:?}"
cp -R "$GPU/AppleParavirtGPUMetalIOGPUFamily.bundle" "$B"
chown -R 0:0 "$B"
find "$B" -type d -exec chmod 755 {} +
find "$B" -type f -exec chmod 644 {} +
# (ls on Linux hfsplus says "No data available" for the bundle's ACLs, as in the hand build: not an error)
ls -l "$B" 2> /dev/null || true
[ -f "$B/AppleParavirtGPUMetalIOGPUFamily" ] && [ -f "$B/libAppleParavirtCompilerPluginIOGPUFamily.dylib" ] ||
	{ echo "the GPU driver did not copy onto the root"; exit 1; }

python3 -I $S/roott-prefs.py $R
python3 -I $S/root26-prefs.py $R
find $R/private/var/mobile/Library/Logs/CrashReporter -maxdepth 1 -name '*.ips' -delete 2> /dev/null || true
cat $P/hashes.txt
df -h $R | tail -1
