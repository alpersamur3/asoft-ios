#!/bin/bash
# Copy the OS image's staged system apps onto a mounted root ($R, from root26-do.sh)
# and run root26-staged.py on it.
set -eu
A=${ASOFT26:?set ASOFT26 to the build folder as WSL sees it, e.g. /mnt/d/ios26}
S=$(cd "$(dirname "$0")" && pwd)
OS=$A/os/094-97246-090.dmg
df -h $R/private/var | tail -1
# The staged apps are only for SystemAppMigrator, which root26-staged.py takes out (nothing installs
# them on HFS+; apply-apps.sh puts the apps into /Applications). ASOFT_KEEP_SYSTEMAPPMIGRATOR=1: as before.
if [ "${ASOFT_KEEP_SYSTEMAPPMIGRATOR:-}" = 1 ]; then
bash $S/m2-peek.sh $OS "cp -a \$M/private/var/staged_system_apps/. $R/private/var/staged_system_apps/ 2>&1 | grep -v 'preserving\|xattr' | head -5; true"
chown 501:501 $R/private/var/staged_system_apps
fi
echo "staged apps: $(ls $R/private/var/staged_system_apps | wc -l), $(du -sh $R/private/var/staged_system_apps | cut -f1)"
python3 $S/root26-staged.py $R
df -h $R/private/var | tail -1
