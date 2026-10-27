#!/bin/bash
# Release staticlib of the reims C API for x86_64-pc-windows-gnu, the native-static-libs rustc
# prints, and a dist tree (lib/, include/, lib/pkgconfig/) for win-build.sh. Run in MSYS2 UCRT64
# (mingw-w64-ucrt-x86_64-rust) from PowerShell:  ucrt.ps1 ios26/scripts/reims-build.sh
# The reims-vgpu checkout (branch windows) needs metal2vulkan's windows branch next to it as
# metal2vulkan-win (see its Cargo.toml).
set -o pipefail
ROOT=${ASOFT26_SRC:?set ASOFT26_SRC to the source folder, e.g. /c/asoft26-src}
R=$ROOT/reims-vgpu
D=$ROOT/reims-dist
mkdir -p "$D/lib/pkgconfig" "$D/include"
cd "$R"
export CARGO_NET_GIT_FETCH_WITH_CLI=true
cargo rustc --release --target x86_64-pc-windows-gnu -p reims-vgpu-c --lib \
    --no-default-features --features "${FEATURES:-vulkan,guest-arm64}" --crate-type staticlib --message-format=short \
    -- --print native-static-libs 2>&1 | tee "$D/build.log" | tail -${1:-40}
rc=${PIPESTATUS[0]}
echo "BUILD_EXIT=$rc"
[ "$rc" = 0 ] || exit "$rc"
A="$R/target/x86_64-pc-windows-gnu/release/libreims_vgpu_c.a"
LIBS=$(grep -o 'native-static-libs: .*' "$D/build.log" | tail -1 | sed 's/native-static-libs: //')
echo "NATIVE_STATIC_LIBS=$LIBS"
cp "$A" "$D/lib/libreims_vgpu.a"
cp "$R/crates/reims-vgpu-c/include/reims_vgpu.h" "$D/include/"
cat > "$D/lib/pkgconfig/reims-vgpu.pc" <<PC
prefix=\${pcfiledir}/../..
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: reims-vgpu
Description: reims-vgpu C API (rvg_*), Vulkan platform, x86_64-pc-windows-gnu (ASoftware port)
Version: 0.1.0
Libs: -L\${libdir} -lreims_vgpu
Libs.private: $LIBS
Cflags: -I\${includedir}
PC
echo "rvg_ symbols: $(nm -g --defined-only "$D/lib/libreims_vgpu.a" 2>/dev/null | grep -c ' T rvg_')"
