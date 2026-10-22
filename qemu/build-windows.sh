#!/bin/bash
# Build our patched qemu-system-aarch64 on a Windows PC, the way .github/workflows/qemu-win.yml
# does on GitHub. Runs in MSYS2's UCRT64 shell, started from PowerShell or cmd (not from Git Bash,
# whose msys runtime clashes with MSYS2's):
#   C:\msys64\msys2_shell.cmd -defterm -here -no-start -ucrt64 -c "bash qemu/build-windows.sh [WORKDIR]"
# Packages it needs, once:
#   pacman -S --needed bison diffutils flex git grep make sed mingw-w64-ucrt-x86_64-{binutils,gcc,
#     pkgconf,ninja,python,python-certifi,python-setuptools,python-wheel,glib2,pixman,zstd,capstone,
#     libslirp,gtk3,libepoxy,angleproject,SDL2}
# WORKDIR (default C:\asoft-build) gets qemu-src (QEMU_REF, default v11.1.2), qemu-build and dist;
# dist holds the .exe with the DLLs it needs, as the CI artifact does.
set -eu
PATCHES=$(cd "$(dirname "$0")" && pwd)/patches
WORK=${1:-/c/asoft-build}
QEMU_REF=${QEMU_REF:-v11.1.2}
SRC=$WORK/qemu-src
BUILD=$WORK/qemu-build
DIST=$WORK/dist
mkdir -p "$WORK"
[ -d "$SRC" ] || git clone -q --depth 1 -b "$QEMU_REF" -c core.autocrlf=false \
    https://github.com/qemu/qemu.git "$SRC"
cd "$SRC"
# the files our patches change back to the plain sources, then the patches (a Windows checkout
# may have given them CRLF ends)
git -c core.filemode=false checkout -q HEAD -- $(sed 's/\r$//' "$PATCHES"/*.patch | sed -n 's#^+++ b/##p' | sort -u)
for p in "$PATCHES"/*.patch; do
    echo "== $(basename "$p")"
    sed 's/\r$//' "$p" | git -c core.filemode=false apply -
done
mkdir -p "$BUILD" && cd "$BUILD"
if [ ! -f build.ninja ]; then
    "$SRC"/configure --target-list=aarch64-softmmu -Ddebug=false \
        --disable-docs --disable-guest-agent \
        --enable-gtk --enable-opengl --enable-sdl --enable-slirp --enable-fdt=internal \
        --with-pkgversion=ASoftware 2>&1 | tail -5
fi
# qemu-img makes the per-user disk overlays (scripts/run-windows.ps1)
ninja qemu-system-aarch64.exe qemu-system-aarch64w.exe qemu-img.exe 2>&1 | tail -3

rm -rf "$DIST" && mkdir -p "$DIST"
cp qemu-system-aarch64.exe qemu-system-aarch64w.exe qemu-img.exe "$DIST"/
# ANGLE: libepoxy loads it at run time for gl=on, so no import table names it
todo="$DIST/qemu-system-aarch64.exe $DIST/qemu-img.exe"
for dll in $(pacman -Ql mingw-w64-ucrt-x86_64-angleproject | awk '/\/bin\/.*\.dll$/ {print $2}'); do
    cp "$dll" "$DIST"/
    todo="$todo $DIST/$(basename "$dll")"
done
# the DLLs from /ucrt64/bin these need, recursively
while [ -n "$todo" ]; do
    next=""
    for f in $todo; do
        for dll in $(objdump -p "$f" | sed -n 's/^\s*DLL Name: //p'); do
            if [ -f "/ucrt64/bin/$dll" ] && [ ! -f "$DIST/$dll" ]; then
                cp "/ucrt64/bin/$dll" "$DIST"/
                next="$next $DIST/$dll"
            fi
        done
    done
    todo="$next"
done
# GTK runtime data: settings schemas and the image loaders for the window icon
mkdir -p "$DIST"/share/glib-2.0/schemas "$DIST"/lib
cp /ucrt64/share/glib-2.0/schemas/gschemas.compiled "$DIST"/share/glib-2.0/schemas/
cp -r /ucrt64/lib/gdk-pixbuf-2.0 "$DIST"/lib/
cp "$SRC"/COPYING "$SRC"/LICENSE "$PATCHES"/*.patch "$DIST"/
echo "QEMU $QEMU_REF ($(git -C "$SRC" rev-parse HEAD)), patched, local build" > "$DIST"/BUILD.txt
"$DIST"/qemu-system-aarch64.exe --version | head -1
