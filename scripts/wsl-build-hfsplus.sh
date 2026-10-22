#!/bin/bash
# The stock WSL2 kernel has no HFS+ driver, but the iOS root image is HFS+.
# Build fs/hfsplus as a module from the exact WSL kernel source tag and load it.
# Must be re-run after a WSL kernel update (the module is tied to `uname -r`).
#   wsl -d ios-emu -u root -- bash scripts/wsl-build-hfsplus.sh
set -euo pipefail

KVER=$(uname -r)                       # 6.6.87.2-microsoft-standard-WSL2
TAG=linux-msft-wsl-${KVER%%-*}         # linux-msft-wsl-6.6.87.2
SRC=/root/work/wsl-kernel/$TAG
DEST=/lib/modules/$KVER/extra
KO=$SRC/fs/hfsplus/hfsplus.ko

if ! grep -q hfsplus /proc/filesystems; then
  # Newer WSL mounts /lib/modules from its own image at every start, so a copy in $DEST is
  # gone after a WSL restart: load the module from the source tree it was built in.
  if [ ! -f "$KO" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq flex bison bc libelf-dev libssl-dev dwarves cpio kmod >/dev/null
    mkdir -p /root/work/wsl-kernel
    if [ ! -d "$SRC" ]; then
      cd /root/work/wsl-kernel
      curl -fsSL "https://github.com/microsoft/WSL2-Linux-Kernel/archive/refs/tags/$TAG.tar.gz" | tar xz
      mv "WSL2-Linux-Kernel-$TAG" "$SRC"
    fi
    cd "$SRC"
    zcat /proc/config.gz > .config
    ./scripts/config --module HFSPLUS_FS
    make olddefconfig >/dev/null
    # Full module build produces Module.symvers with the same symbol CRCs as the running kernel
    make -j"$(nproc)" modules > /root/work/wsl-kernel/build.log 2>&1
    test -f "$KO"
  fi
  insmod "$KO"
fi
grep hfsplus /proc/filesystems
