# The visionOS root's changes before its first boot, sourced by Install-visionOS.ps1's patches step inside
# in_root ($R = the root, p1, with the Data volume p2 on $R/private/var; S = the scripts; P = where the
# patched copies and their CDHashes go, P/hashes.txt for the trust cache; GPU = the gpu step's folder;
# ROOMS / NOAUDIO = the rooms step's folders; AUDIO = the audio step's VPhoneVirtIOSound.driver, or empty).
# The hand-built chain (notes/VISIONOS-INSTALL.md section 3) flattened; each part is what a measured boot needed:
#  - root26-tweaks.py: com.asoft.bash on the serial console, _PanicOnCrash renamed, containers
#  - rootx-jobs.py: SurfBoard loads under the diagnostics osenvironment, SurfBoard/backboardd without _Conclave
#  - the system keybag, as ios26's tweaks step makes it
#  - libsystem_darwin's lockdown-mode block: absent in 24N120 (0 hits required: a hit means another build)
#  - IOMobileFramebuffer force-kern: dscforce.py, 10 trampolines in one subcache (the paravirtual scanout)
#  - /sbin/launchd: _sandbox_check_by_audit_token stub -> allow (launchd-sbx.py; the 26.4 kernel's platform
#    sandbox has no polaris/UXM/wakeboard rules), re-attested
#  - the staged system apps as built-in apps; the LaunchServices database goes stale
#  - libxpc _xpc_token_satisfies_lwcr derives matched from error_code (the 26.4 kernel's AMFI answers a 27.x
#    client inconsistently, and os_crash killed every daemon with a peer requirement)
#  - RealityLauncher's long press to edit 0.5 -> 3 s (rootx-lp.py: under TCG a tap became a long press), re-attested
#  - the guest GPU driver (the gpu step's copy, retargeted to visionOS and signed)
#  - rootx-prefs.py (onboarding skipped, UXM's camera plugin denied, watchdogs off), root26-prefs.py (it also
#    moves VirtualAudio.plugin to HAL.disabled: the silent state; the disks step's sound layer moves it back)
#  - FeatureFlags: RealityEnvironment/ShowEnvironmentsOnSimulator on (the places), RealityLauncher's
#    StereoEnvironmentIcons off
#  - the churn cuts (rootx-churn.py on, 24 jobs; rootx-churn2.py, 5 telemetry jobs)
#  - the simulator runtime's six synthetic rooms, their usdc without the acoustic prims (backboardd aborted
#    building PHASEMaterials on the silent disk)
#  - with AUDIO: VPhoneVirtIOSound.driver (virtio-snd HAL plug-in) and /Library/Audio/Tunings/AID0 -> AID10001
#  - the keyboard camera: W/A/S/D and the other head keys move the head only while HID usage 0x6C (F13) is
#    held, which QEMU's walk mode holds (dsc-keycam.py, after the other shared-cache patches)
set -euo pipefail
: "${R:?}" "${S:?}" "${P:?}" "${GPU:?}" "${ROOMS:?}" "${NOAUDIO:?}"
AUDIO=${AUDIO:-}
C=$R/System/Library/Caches/com.apple.dyld
mkdir -p "$P"
: > "$P/hashes.txt"
python3 -I -c 'import plistlib, sys; sys.exit(plistlib.load(open(sys.argv[1], "rb")).get("ProductBuildVersion") != "24N120")' \
	$R/System/Library/CoreServices/SystemVersion.plist || { echo "this root is not visionOS 27.2 (24N120)"; exit 1; }

python3 -I $S/root26-tweaks.py $R
python3 -I $S/rootx-jobs.py $R
install -d -m 0700 -o 0 -g 0 $R/private/var/keybags
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>' \
	> $R/private/var/keybags/systembag.kb
chown 0:0 $R/private/var/keybags/systembag.kb
chmod 0600 $R/private/var/keybags/systembag.kb

# dsc_hits NAME HEX: how many times HEX is in the cache (dscfind.py's listing in $P/NAME-find.txt)
dsc_hits() {
	python3 -I $S/dscfind.py $C "$2" 0x10 > "$P/$1-find.txt" || { echo "dscfind.py failed on $C" >&2; exit 1; }
	grep -c ' va ' "$P/$1-find.txt" || true
}
# dsc_put LISTING: the patched subcache LISTING's last line names (in $P) over the cache's, its CDHash kept
dsc_put() {
	local f
	f=$(tail -1 "$1" | awk '{print $1}')
	[ -f "$P/$f" ] || { echo "no patched $f in $P"; exit 1; }
	cat "$P/$f" > "$C/$f"
	cmp "$P/$f" "$C/$f"
	tail -1 "$1" | awk '{print $3}' >> "$P/hashes.txt"
	rm -f "${P:?}/$f"
	echo "patched $f"
}
# Mach-O: patched with PATCHER (ORIG OUT [ARGS]) into $P, re-attested, put back; its new CDHash kept
macho_patch() {
	local path=$1 name=$2; shift 2
	cp "$path" "$P/$name.orig"
	"$@" "$P/$name.orig" "$P/$name"
	python3 -I $S/reattest.py "$P/$name.orig" "$P/$name" | tee "$P/$name.txt"
	cat "$P/$name" > "$path"
	cmp "$P/$name" "$path"
	awk 'NR==1{print $2}' "$P/$name.txt" >> "$P/hashes.txt"
	rm -f "$P/$name" "$P/$name.orig"
	echo "patched ${path#$R}"
}

n=$(dsc_hits lockdown 1f04003120010054e80740f91f0500f1e8179f1a)
[ "$n" = 0 ] || { cat "$P/lockdown-find.txt"; echo "lockdown pattern: $n hits, expected 0 on 24N120"; exit 1; }
python3 -I $S/dscforce.py $C $S/iomfb-syms.txt $P | tee $P/iomfb.txt
dsc_put $P/iomfb.txt
lsbx() { python3 -I $S/launchd-sbx.py "$@"; }
macho_patch $R/sbin/launchd launchd lsbx

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

n=$(dsc_hits lwcr e8079f1a0800084a88010036)
[ "$n" = 1 ] || { cat "$P/lwcr-find.txt"; echo "lwcr pattern: $n hits, expected 1"; exit 1; }
va=$(awk '/ va /{print $NF}' "$P/lwcr-find.txt")
python3 -I $S/dsc-patch.py $C $va e8079f1a0800084a88010036 e0179f1a1f2003d51f2003d5 $P | tee $P/lwcr.txt
dsc_put $P/lwcr.txt
lp() { python3 -I $S/rootx-lp.py "$1" "$2" 3.0; }
macho_patch $R/Applications/RealityLauncher.app/RealityLauncher RealityLauncher lp

B=$R/System/Library/Extensions/AppleParavirtGPUMetalIOGPUFamily.bundle
rm -rf "${B:?}"
cp -R "$GPU/AppleParavirtGPUMetalIOGPUFamily.bundle" "$B"
chown -R 0:0 "$B"
find "$B" -type d -exec chmod 755 {} +
find "$B" -type f -exec chmod 644 {} +
ls -l "$B"

python3 -I $S/rootx-prefs.py $R
python3 -I $S/root26-prefs.py $R
python3 -I $S/rootx-envff.py $R
python3 -I $S/rootx-rlstereo.py $R
python3 -I $S/rootx-churn.py $R on
python3 -I $S/rootx-churn2.py $R

# the synthetic rooms at the path SystemEnvironments reads, root:wheel 755/644, then the usdc without audio
D=$R/System/Library/Assets/SystemEnvironments/SyntheticEnvironments
mkdir -p $D
rsync -rlt "$ROOMS/" "$D/" 2>&1 | grep -v 'No data available' || true
[ "$(find "$ROOMS" -type f | wc -l)" = "$(find $D -type f | wc -l)" ] || { echo "the rooms did not all copy onto the root"; exit 1; }
for f in "$NOAUDIO"/*/*.usdc; do
	r=$(basename "$(dirname "$f")") u=$(basename "$f")
	[ -f "$D/$r/AssetData/$u" ] || { echo "no $r/AssetData/$u among the rooms"; exit 1; }
	cat "$f" > "$D/$r/AssetData/$u"
	cmp "$f" "$D/$r/AssetData/$u"
done
chown -R 0:0 $R/System/Library/Assets
find $R/System/Library/Assets -type d -exec chmod 755 {} +
find $R/System/Library/Assets -type f -exec chmod 644 {} +
echo "rooms: $(ls $D | tr '\n' ' ')($(du -sh $D | cut -f1))"

if [ -n "$AUDIO" ]; then
	H=$R/System/Library/Audio/Plug-Ins/HAL
	V=$H/VPhoneVirtIOSound.driver
	[ -d $H ] || { echo "no HAL plug-in folder on the root"; exit 1; }
	rm -rf "${V:?}"; mkdir -p $V/_CodeSignature
	for f in VPhoneVirtIOSound Info.plist _CodeSignature/CodeResources; do cat "$AUDIO/$f" > "$V/$f"; cmp "$AUDIO/$f" "$V/$f"; done
	chown -R 0:0 $V; chmod 755 $V $V/_CodeSignature $V/VPhoneVirtIOSound; chmod 644 $V/Info.plist $V/_CodeSignature/CodeResources
	# VirtualAudio's DSP tunings: the guest's tree has no acoustic id, so it reads AID0; N301's first is AID10001
	T=$R/Library/Audio/Tunings
	[ -d $T/AID10001 ] || { echo "no $T/AID10001 on the root"; exit 1; }
	ln -sfn AID10001 $T/AID0
	echo "VPhoneVirtIOSound.driver and AID0 -> AID10001"
else
	echo "no audio plug-in: the root gets no VPhoneVirtIOSound.driver (silent only)"
fi

python3 -I $S/dsc-keycam.py $C $P | tee $P/keycam.txt
if [ "$(awk 'NR==1{print $4}' $P/keycam.txt)" = already ]; then
	awk 'NR==1{print $3}' $P/keycam.txt >> "$P/hashes.txt"
	echo "the keyboard camera patch was there already"
else
	dsc_put $P/keycam.txt
fi

find $R/private/var/mobile/Library/Logs/CrashReporter -maxdepth 1 -name '*.ips' -delete 2> /dev/null || true
cat $P/hashes.txt
df -h $R | tail -1
