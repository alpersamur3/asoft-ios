#!/bin/bash
# Build qemu-sptm (with -M vresearch) for Windows in MSYS2 UCRT64. Start it from
# PowerShell, not Git Bash (their msys runtimes clash):
#   C:\msys64\msys2_shell.cmd -defterm -here -no-start -ucrt64 -c "bash ios26/scripts/win-build.sh [jobs]"
# apple-aes needs a crypto backend: a static nettle 3.10 from win-nettle.sh
# (MSYS2's nettle 4.0 doesn't build with QEMU 11.1). pvg=reims needs the
# reims-vgpu library (reims-dist, built by reims-build.sh); the
# build reconfigures when the tree was configured without it, and when it was
# configured without GTK (the window: -display gtk,gl=on,sidebar=on, as the
# iOS 16 build). Output: $DIST (default <ASOFT26_SRC>/dist), copy it to <Work>\qemu (exe + DLLs + GTK runtime data).
set -eu
# the source folder: qemu-sptm, reims-vgpu, metal2vulkan-win checkouts, deps, reims-dist
ROOT=${ASOFT26_SRC:?set ASOFT26_SRC to the source folder, e.g. /c/asoft26-src}
HERE=$(cd "$(dirname "$0")" && pwd)
export PKG_CONFIG_PATH=$ROOT/deps/nettle/lib/pkgconfig:$ROOT/reims-dist/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
J=${1:-8}
SRC=$ROOT/qemu-sptm
B=$ROOT/build-qemu
DIST=${DIST:-$ROOT/dist}
mkdir -p $B && cd $B
if [ -f build.ninja ] && ! grep -q '#define CONFIG_REIMS_VGPU' config-host.h 2>/dev/null; then
	echo "reconfiguring: no CONFIG_REIMS_VGPU in the current configuration"
	rm -f build.ninja
fi
if [ -f build.ninja ] && ! grep -q '#define CONFIG_GTK' config-host.h 2>/dev/null; then
	echo "reconfiguring: no CONFIG_GTK in the current configuration"
	rm -f build.ninja
fi
if [ ! -f build.ninja ]; then
	$SRC/configure --target-list=aarch64-softmmu -Ddebug=false \
		--disable-docs --disable-guest-agent --disable-werror \
		--enable-gtk --enable-opengl --disable-sdl --disable-vnc \
		--enable-slirp --enable-nettle --enable-fdt=internal \
		--enable-reims-vgpu \
		--with-pkgversion=ASoftware-ios26 2>&1 | tail -25
fi
# qemu-system-aarch64w.exe: the same without a console window, for the GTK window
ninja -j$J qemu-system-aarch64.exe qemu-system-aarch64w.exe 2>&1 | grep -E 'error|FAILED|warning: implicit|Linking target' | tail -20
rm -rf $DIST && mkdir -p $DIST
cp qemu-system-aarch64.exe qemu-system-aarch64w.exe $DIST/
# ANGLE: libepoxy loads it at run time for gl=on, so no import table names it
todo="$DIST/qemu-system-aarch64.exe"
for dll in $(pacman -Ql mingw-w64-ucrt-x86_64-angleproject | awk '/\/bin\/.*\.dll$/ {print $2}'); do
	cp "$dll" $DIST/
	todo="$todo $DIST/$(basename "$dll")"
done
# the DLLs from /ucrt64/bin these need, recursively
while [ -n "$todo" ]; do
	next=""
	for f in $todo; do
		for dll in $(objdump -p "$f" | sed -n 's/^\s*DLL Name: //p'); do
			if [ -f "/ucrt64/bin/$dll" ] && [ ! -f "$DIST/$dll" ]; then
				cp "/ucrt64/bin/$dll" $DIST/
				next="$next $DIST/$dll"
			fi
		done
	done
	todo="$next"
done
# GTK runtime data: settings schemas and the image loaders for the window icon
mkdir -p $DIST/share/glib-2.0/schemas $DIST/lib
cp /ucrt64/share/glib-2.0/schemas/gschemas.compiled $DIST/share/glib-2.0/schemas/
cp -r /ucrt64/lib/gdk-pixbuf-2.0 $DIST/lib/
# the window icon and side bar logo (ui/gtk: ASoftware's look)
cp "$HERE/../../assets/logo-256.png" $DIST/asoftware.png
cp $SRC/COPYING $SRC/LICENSE $DIST/
echo "qemu-sptm $(git -C $SRC rev-parse --short HEAD)+local, -M vresearch" > $DIST/BUILD.txt
$DIST/qemu-system-aarch64.exe --version | head -1
$DIST/qemu-system-aarch64.exe -M help | grep -E 'vresearch|darwin'
