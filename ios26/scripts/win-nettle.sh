#!/bin/bash
# Static nettle + hogweed 3.10.1 (QEMU wants hogweed once it finds gmp) for the Windows QEMU build, in our own prefix (MSYS2's
# package is nettle 4.0, whose headers QEMU 11.1 doesn't build against).
# (-std=gnu17: GCC 16 defaults to C23, which breaks its getopt.h; no assembler: needs m4)
# Source: <ASOFT26_SRC>\deps\dl\nettle-3.10.1.tar.gz (GNU, signature checked). From PowerShell:
#   C:\msys64\msys2_shell.cmd -defterm -here -no-start -ucrt64 -c "bash ios26/scripts/win-nettle.sh"
set -eu
D=${ASOFT26_SRC:?set ASOFT26_SRC to the source folder}/deps
rm -rf $D/build && mkdir -p $D/build && cd $D/build
tar xzf $D/dl/nettle-3.10.1.tar.gz
cd nettle-3.10.1
CFLAGS="-O2 -std=gnu17" ./configure --prefix=$D/nettle --disable-shared --enable-static \
	--disable-documentation --disable-openssl --disable-assembler > ../configure.log 2>&1
make -j8 > ../make.log 2>&1
make install > ../install.log 2>&1
# meson runs the native (Windows) python and gcc: no MSYS path translation
sed -i -E 's|^prefix=/([a-z])/|prefix=\U\1\E:/|' $D/nettle/lib/pkgconfig/nettle.pc $D/nettle/lib/pkgconfig/hogweed.pc
ls $D/nettle/lib $D/nettle/lib/pkgconfig $D/nettle/include/nettle | head -20
