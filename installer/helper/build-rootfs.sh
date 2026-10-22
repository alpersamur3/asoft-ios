#!/bin/bash
# Build the helper VM's root, an initramfs, into OUT/initrd.gz: Ubuntu 24.04 arm64
# packages (extracted, no maintainer scripts run, so no arm64 emulation is needed),
# apfs-fuse cross-compiled against them, and the helper's own scripts.
#   build-rootfs.sh APFS_FUSE_SRC OUT [ASOFTINSTALLD]
# Runs as root on an x86_64 Linux (the ios-emu WSL distro) with mmdebstrap, cmake and
# g++-aarch64-linux-gnu. ASOFTINSTALLD (apps/asoftinstalld, built by the ios-apps
# workflow) goes into the disks the helper builds.
set -euo pipefail
apfs_src=$(realpath "$1") out=$(realpath -m "$2") daemon=${3:-}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
mirror=http://ports.ubuntu.com/ubuntu-ports
work=$out/rootfs-build
mkdir -p "$work"

# What the jobs run: shells and core tools, HFS+ and ext4 (scratch) tools, rsync, Python (the iOS root
# tweaks and plist edits), FUSE 3 for apfs-fuse, busybox for the odd extra tool.
runtime=bash,dash,coreutils,util-linux,mount,findutils,grep,sed,gzip,hfsprogs,e2fsprogs,rsync,python3,fuse3,libfuse3-3,zlib1g,libbz2-1.0,libstdc++6,busybox-static
# Headers and libraries apfs-fuse builds against (its sysroot)
devel=libc6-dev,libstdc++-13-dev,libfuse3-dev,zlib1g-dev,libbz2-dev,libattr1-dev

extract() {    # extract DIR PACKAGES
    rm -rf "$1"
    mmdebstrap --quiet --mode=root --variant=extract --arch=arm64 --components=main,universe \
        --include="$2" noble "$1" "$mirror"
    # merged /usr, as Ubuntu has it (the packages ship their files under usr/)
    for d in bin sbin lib; do
        [ -e "$1/$d" ] || ln -s "usr/$d" "$1/$d"
    done
}

extract "$work/root" "$runtime"
extract "$work/sysroot" "$devel"

# apfs-fuse for arm64 (FUSE 3), linked against the sysroot's libraries
cat > "$work/aarch64.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_SYSROOT $work/sysroot)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF
rm -rf "$work/apfs-fuse"
cmake -S "$apfs_src" -B "$work/apfs-fuse" -DCMAKE_TOOLCHAIN_FILE="$work/aarch64.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DUSE_FUSE3=ON >/dev/null
make -C "$work/apfs-fuse" -j"$(nproc)" apfs-fuse 2>&1 | grep -E 'error|Built target apfs-fuse' || true
install -D -m 755 "$work/apfs-fuse/apfs-fuse" "$work/root/usr/local/bin/apfs-fuse"

# Trim what no job uses
rm -rf "$work/root"/usr/share/{doc,man,info,locale,lintian,bash-completion} \
    "$work/root"/usr/lib/python3.12/{test,ensurepip,idlelib,tkinter,lib2to3,turtledemo,pydoc_data} \
    "$work/root"/var/cache/apt "$work/root"/var/lib/apt/lists

# The helper: /init, the jobs, and the repo tools they use
install -m 755 "$here/init" "$work/root/init"
install -d "$work/root/asoft"
install -m 755 "$here"/job-*.sh "$here"/ipsw-members.py "$work/root/asoft/"
install -m 755 "$repo/tools/mkiosroot.sh" "$repo/tools/sweet-root-tweaks.py" "$repo/tools/asoft-disk.sh" \
    "$work/root/asoft/"
[ -z "$daemon" ] || install -m 755 "$daemon" "$work/root/asoft/asoftinstalld"
# mkiosroot.sh runs its privileged steps through sudo; the helper is root already
printf '#!/bin/sh\nexec "$@"\n' > "$work/root/usr/local/bin/sudo"
chmod 755 "$work/root/usr/local/bin/sudo"
mkdir -p "$work/root"/{proc,sys,dev,tmp,run,mnt}

(cd "$work/root" && find . -print0 | cpio --null -o -H newc --quiet) | gzip -6 > "$out/initrd.gz"
du -sh "$work/root"
ls -la "$out/initrd.gz"
