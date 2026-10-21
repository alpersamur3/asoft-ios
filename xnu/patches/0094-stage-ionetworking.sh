#!/bin/bash
# Stage Apple's open source IONetworkingFamily for SWEET, built into the kernel
# (iokit/sweet_net, headers in iokit/IOKit/network): with it a virtio-net
# controller (iokit/Kernel/arm/SweetVirtioNet.cpp) gives iOS a real IOKit
# network interface, which configd needs before it names, configures and
# uses an interface (a bare ifnet stays invisible to it).
# dxb runs patches/*.sh from the XNU source root before applying *.patch.
set -euo pipefail

[[ "${MACHINE_CONFIG:-}" == SWEET ]] || exit 0
[[ "${MACOS_VERSION:-}" == 13.5 ]] || {
    echo 'SWEET IONetworkingFamily integration requires xnu-8796.141.3 (macOS 13.5)' >&2
    exit 1
}
[[ -f iokit/KernelConfigTables.cpp ]] || exit 1

# IONetworkingFamily-170.140.2 is paired with xnu-8796.141.3 in Apple's
# macos-135 release.json. Fetch the immutable commit, never a moving tag.
net_sha=f9f7e57b2132b82de09a26ddcbf56fd8125b4933
net_tmp=$(mktemp -d)
trap 'rm -rf "$net_tmp"' EXIT
git init -q "$net_tmp"
git -C "$net_tmp" fetch -q --depth 1 \
    https://github.com/apple-oss-distributions/IONetworkingFamily "$net_sha"
git -C "$net_tmp" checkout -q FETCH_HEAD
[[ "$(git -C "$net_tmp" rev-parse HEAD)" == "$net_sha" ]]

if [[ -e iokit/sweet_net || -e iokit/IOKit/network ]]; then
    echo 'refusing to overwrite existing IONetworkingFamily sources' >&2
    exit 1
fi
# Preserve upstream copyright/license headers; no downloaded sources in git.
# The sources include their private headers as "X.h" and the public ones as
# <IOKit/network/X.h>; every header goes to both places.
mkdir -p iokit/sweet_net iokit/IOKit/network
cp "$net_tmp"/*.cpp "$net_tmp"/*.h iokit/sweet_net/
cp "$net_tmp"/*.h iokit/IOKit/network/

# Kernel builds use -nostdinc; IONetworkInterface.cpp needs the SDK's target
# macros (iokit/conf/Makefile.template adds -I iokit/sweet_net). Off the
# macOS runner (a local tree only for writing patches) there is no SDK.
if command -v xcrun >/dev/null; then
    cp "$(xcrun --sdk macosx --show-sdk-path)/usr/include/TargetConditionals.h" iokit/sweet_net/
fi
echo "Staged IONetworkingFamily-170.140.2 ($net_sha) for SWEET"
