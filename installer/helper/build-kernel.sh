#!/bin/bash
# Build the helper VM's arm64 kernel (Linux, cross-compiled) into OUT/Image.gz.
#   build-kernel.sh SRC OUT      SRC: a Linux source tree (any recent version)
# Runs on an x86_64 Linux (the ios-emu WSL distro) with gcc-aarch64-linux-gnu.
set -euo pipefail
src=$(realpath "$1") out=$(realpath -m "$2")
here=$(cd "$(dirname "$0")" && pwd)
build=$out/kernel-build
mkdir -p "$build"
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make -C "$src" O="$build" defconfig >/dev/null
"$src"/scripts/kconfig/merge_config.sh -m -O "$build" "$build/.config" "$here/kernel.config" >/dev/null
make -C "$src" O="$build" olddefconfig >/dev/null
# what the fragment asked for must have survived olddefconfig
while IFS= read -r line; do
    case $line in CONFIG_*) grep -qx "$line" "$build/.config" || { echo "kernel config lost: $line" >&2; exit 1; };; esac
done < "$here/kernel.config"
make -C "$src" O="$build" -j"$(nproc)" Image 2>&1 | grep -E '^(  LD|  OBJCOPY)|error' | tail -5
gzip -9 -c "$build/arch/arm64/boot/Image" > "$out/Image.gz"
ls -la "$out/Image.gz"
