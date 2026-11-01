#!/bin/bash
# The Collections wallpaper (README.md, step 5.3.6) on a mounted root ($R, from root26-do.sh):
#  - writes NEW_DIR's dyld_shared_cache_arm64e.42 over the image's (cat >, which keeps the hard link
#    and the owner and mode), after checking the image still has ORIG_DIR's, the subcache the patch
#    was made from (or has NEW_DIR's already)
#  - removes PosterBoard's poster store from its data container, so its next first run sets the
#    Collections wallpaper up
#   root26-do.sh root-collections.qcow2 'bash wp-apply.sh ORIG_DIR NEW_DIR'
set -eu
ORIG=$1 NEW=$2
C=$R/System/Cryptexes/OS/System/Library/Caches/com.apple.dyld
n=dyld_shared_cache_arm64e.42
cur=$(sha256sum < "$C/$n" | cut -c1-16)
orig=$(sha256sum < "$ORIG/$n" | cut -c1-16)
new=$(sha256sum < "$NEW/$n" | cut -c1-16)
if [ "$cur" = "$new" ]; then
	echo "$n already patched"
elif [ "$cur" != "$orig" ]; then
	echo "$n on disk ($cur) is neither $ORIG's nor $NEW's; stop"
	exit 1
else
	cat "$NEW/$n" > "$C/$n"
	echo "$n replaced ($cur -> $(sha256sum < "$C/$n" | cut -c1-16))"
fi
for m in "$R"/private/var/mobile/Containers/Data/Application/*/.com.apple.mobile_container_manager.metadata.plist; do
	[ -f "$m" ] || continue
	grep -q com.apple.PosterBoard "$m" || continue
	d=$(dirname "$m")/Library/Application\ Support/PRBPosterExtensionDataStore
	if [ -e "$d" ]; then
		rm -rf "${d:?}"
		echo "removed ${d#$R}"
	fi
done
