# The watchOS root's changes before its first boot, sourced by Install-watchOS.ps1's patches step inside
# in_root ($R = the root, p1, with the Data volume p2 on $R/private/var; S = the scripts; P = where the
# patched shared-cache copies and their CDHashes go, P/hashes.txt for the trust cache). Each part is what
# a measured boot needed (notes: WATCHOS.md):
#  - root26-tweaks.py: com.asoft.bash on the serial console, _PanicOnCrash renamed, containers
#  - rootw-jobs.py: Carousel loads under the diagnostics osenvironment, Carousel and backboardd lose _Conclave
#  - the system keybag, as ios26's tweaks step makes it
#  - three shared-cache patches (each pattern must match once):
#    libsystem_darwin ___os_lockdown_mode_enabled_block_invoke: the b.eq to os_crash after
#    sysctlbyname("security.mac.lockdown_mode_state_public") == -1 becomes a nop (the 26.4 kernel has no
#    such sysctl); IOMobileFramebuffer force-kern (dscforce.py, 10 trampolines: the paravirtual scanout);
#    libxpc _xpc_token_satisfies_lwcr derives matched from error_code (the 26.4 kernel's AMFI answers a
#    27.x client inconsistently, and os_crash killed every daemon with a peer requirement)
#  - root26-prefs.py: DataMigration not run, watchdogs off; activation once mobileactivationd's container
#    exists (the activation step runs it again after the first boot)
#  - rootw-nobuddy.py: Setup (iPhone pairing) skipped
#  - nanotimekitd's MappedImageCache, which its sandbox may write in but not create
#  - rootw-screen.py: the display stays on (no wrist or eye sensors), FrontBoard watchdogs off
#  - the staged system apps as built-in apps (watchOS installs them from staged_system_apps during
#    Setup/DataMigration through APFS clones; we skip both); the LaunchServices database goes stale
set -euo pipefail
: "${R:?}" "${S:?}" "${P:?}"
C=$R/System/Library/Caches/com.apple.dyld
mkdir -p "$P"
: > "$P/hashes.txt"

python3 -I $S/root26-tweaks.py $R
python3 -I $S/rootw-jobs.py $R
install -d -m 0700 -o 0 -g 0 $R/private/var/keybags
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>' \
	> $R/private/var/keybags/systembag.kb
chown 0:0 $R/private/var/keybags/systembag.kb
chmod 0600 $R/private/var/keybags/systembag.kb

# dsc_site NAME HEX BEFORE_BYTES: the cache VA of HEX's single hit (+ BEFORE_BYTES into it); called as
# va=$(dsc_site ...), so what it says on a miss goes to stderr, where the log sees it
dsc_site() {
	python3 -I $S/dscfind.py $C "$2" 0x10 > "$P/$1-find.txt" || { echo "dscfind.py failed on $C" >&2; exit 1; }
	local n
	n=$(grep -c ' va ' "$P/$1-find.txt" || true)
	[ "$n" = 1 ] || { cat "$P/$1-find.txt"; echo "$1: $n hits of its pattern, expected 1 (another watchOS build?)"; } >&2
	[ "$n" = 1 ] || exit 1
	python3 -c "print(hex(int('$(awk '/ va /{print $NF}' "$P/$1-find.txt")', 16) + $3))"
}
# dsc_put LISTING: the patched subcache LISTING's first line names (in $P) over the cache's, its CDHash kept
dsc_put() {
	local f
	f=$(tail -1 "$1" | awk '{print $1}')
	cat "$P/$f" > "$C/$f"
	cmp "$P/$f" "$C/$f"
	tail -1 "$1" | awk '{print $3}' >> "$P/hashes.txt"
	rm -f "${P:?}/$f"
	echo "patched $f"
}
va=$(dsc_site lockdown 1f04003120010054e80740f91f0500f1e8179f1a 4)
python3 -I $S/dsc-patch.py $C $va 20010054 1f2003d5 $P | tee $P/lockdown.txt
dsc_put $P/lockdown.txt
python3 -I $S/dscforce.py $C $S/iomfb-syms.txt $P | tee $P/iomfb.txt
dsc_put $P/iomfb.txt
va=$(dsc_site lwcr e8079f1a0800084a88010036 0)
python3 -I $S/dsc-patch.py $C $va e8079f1a0800084a88010036 e0179f1a1f2003d51f2003d5 $P | tee $P/lwcr.txt
dsc_put $P/lwcr.txt

python3 -I $S/root26-prefs.py $R
python3 -I $S/rootw-nobuddy.py $R
M=$R/private/var/mobile/Library/Caches/MappedImageCache
install -d -o 501 -g 501 -m 0755 $M $M/com.apple.nanotimekit.ClockFaceSnapshots
python3 -I $S/rootw-screen.py $R

# rsync, not cp -a: Linux hfsplus answers "No data available" when cp preserves permissions (ACLs)
st=$R/private/var/staged_system_apps
ap=$R/Applications
n=0
for p in $st/*.app; do
	a=${p##*/}
	[ -e "$ap/$a" ] && continue
	rsync -rlptgo "$p/" "$ap/$a/" 2>&1 | grep -v 'No data available' || true
	chown -R 0:0 "$ap/$a"; chown 0:80 "$ap/$a"; chmod 775 "$ap/$a"
	n=$((n + 1))
done
echo "staged apps made built-in: $n; in /Applications: $(ls -d $ap/*.app | wc -l)"
# (a root that never booted has neither folder yet: find fails, which is no error here)
{ find $R/private/var/mobile/Containers/Data/InternalDaemon $R/private/var/containers/Data/System -maxdepth 5 \
	-name 'com.apple.LaunchServices-*.csstore' 2> /dev/null || true; } | while read -r f; do mv "$f" "$f.stale"; done
find $R/private/var/mobile/Library/Logs/CrashReporter -maxdepth 1 -name '*.ips' -delete 2> /dev/null || true
cat $P/hashes.txt
df -h $R | tail -1
