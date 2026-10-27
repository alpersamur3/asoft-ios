#!/bin/bash
# On a mounted root ($R, from root26-do.sh):
#  - the patched dyld cache subcache(s) in $A/dscpatch replace the OS cryptex's,
#    after checking the disk still has the unpatched original ($A/dsc)
#  - the OS image's deletable system apps go into /Applications as built-in apps (iOS 26
#    installs them from /private/var/staged_system_apps through MobileInstallation, which
#    needs APFS clones; on HFS+ every install fails and the staging copies get removed)
#  - the LaunchServices database is renamed *.stale so lsd registers everything again
set -eu
A=${ASOFT26:?set ASOFT26 to the build folder as WSL sees it, e.g. /mnt/d/ios26}
S=$(cd "$(dirname "$0")" && pwd)
OS=$A/os/094-97246-090.dmg
C=$R/System/Cryptexes/OS/System/Library/Caches/com.apple.dyld
for f in $A/dscpatch/dyld_shared_cache_arm64e*; do
	n=$(basename $f)
	a=$(sha256sum < $C/$n | cut -c1-16); b=$(sha256sum < $A/dsc/$n | cut -c1-16)
	if [ "$a" != "$b" ]; then
		[ "$a" = "$(sha256sum < $f | cut -c1-16)" ] && { echo "$n already patched"; continue; }
		echo "$n on disk is neither the original nor the patch; stop"; exit 1
	fi
	cat $f > $C/$n		# keeps owner and mode
	echo "$n replaced"
done
bash $S/m2-peek.sh $OS "
cd \$M/private/var/staged_system_apps
for a in *.app; do
	case \"\$a\" in AppleVisionProApp.app|'Image Playground.app') continue;; esac
	[ -e \"$R/Applications/\$a\" ] && continue
	cp -a \"\$a\" \"$R/Applications/\" 2>/dev/null || cp -a \"\$a\" \"$R/Applications/\" 2>&1 | grep -v xattr | head -3
	chown -R 0:0 \"$R/Applications/\$a\"; chown 0:80 \"$R/Applications/\$a\"; chmod 775 \"$R/Applications/\$a\"
done"
echo "apps in /Applications: $(ls -d $R/Applications/*.app | wc -l)"
find $R/private/var/mobile/Containers/Data/InternalDaemon -maxdepth 4 -name 'com.apple.LaunchServices-*.csstore' 2>/dev/null | while read f; do mv "$f" "$f.stale"; echo "stale: ${f#$R}"; done
df -h $R | tail -1
