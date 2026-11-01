#!/bin/bash
# The WSL side of Install-iOS26.ps1: the tools README.md's Build steps run in WSL (README.md,
# Build, "You need"). Run as root in the build distro (Ubuntu 24.04):
#   wsl-setup.sh check      one "ok"/"missing" line per tool; exit 1 if one is missing. Reads only.
#   wsl-setup.sh install    install what is missing, then check:
#     apt: qemu-utils hfsprogs gdisk rsync fuse3 kmod util-linux file curl python3 (and the
#          build tools for apfs-fuse and the hfsplus module)
#     ipsw 3.1.739 (blacktop/ipsw's release, SHA-256 checked) into /usr/local/bin
#     apfs-fuse (sgan81/apfs-fuse at a pinned commit, FUSE 3) into /usr/local/bin
#     the hfsplus module for this WSL kernel (wsl-build-hfsplus.sh next to this script: WSL's
#     kernel has none; built from Microsoft's source for `uname -r`, about 5 GB and 20-60 min)
# env: ASOFT26_LINUX (default /root/ios26), the build's scratch space
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=${ASOFT26_LINUX:-/root/ios26}
KVER=$(uname -r)
KO=/root/work/wsl-kernel/linux-msft-wsl-${KVER%%-*}/fs/hfsplus/hfsplus.ko
IPSW_VER=3.1.739
IPSW_URL=https://github.com/blacktop/ipsw/releases/download/v$IPSW_VER/ipsw_${IPSW_VER}_linux_x86_64.tar.gz
IPSW_SHA256=8124bdba7902e7627bae1bb2e1117c9cfcdc31de0f65ec55e341565ac6029a01
APFS_FUSE_URL=https://github.com/sgan81/apfs-fuse
APFS_FUSE_COMMIT=66b86bd525e8cb90f9012543be89b1f092b75cf3
APT_RUN="qemu-utils hfsprogs gdisk rsync fuse3 kmod util-linux file curl ca-certificates python3"
APT_BUILD="git cmake g++ make libfuse3-dev zlib1g-dev libbz2-dev libattr1-dev"

# python3 must be the x86-64 one: a foreign-arch (arm64) python3.12-minimal leaves an
# interpreter WSL cannot run ("exec format error")
python_ok() { python3 -c 'import plistlib, struct, zlib' 2> /dev/null; }

check() {
	local bad=0 t
	ok() { printf 'ok       %-12s %s\n' "$1" "$2"; }
	no() { printf 'missing  %-12s %s\n' "$1" "$2"; bad=1; }
	if grep -q '^ID=ubuntu' /etc/os-release 2> /dev/null; then
		ok distro "$(. /etc/os-release; echo "$PRETTY_NAME"), kernel $KVER"
	else
		no distro "not Ubuntu ($(. /etc/os-release 2> /dev/null; echo "${PRETTY_NAME:-unknown}")): the install mode uses apt"
	fi
	[ "$(id -u)" = 0 ] && ok root "running as root" || no root "run as root (wsl -u root)"
	for t in qemu-img:qemu-utils qemu-nbd:qemu-utils mkfs.hfsplus:hfsprogs fsck.hfsplus:hfsprogs \
		sgdisk:gdisk rsync:rsync fusermount:fuse3 insmod:kmod losetup:util-linux curl:curl; do
		if command -v "${t%%:*}" > /dev/null; then ok "${t%%:*}" "$(command -v "${t%%:*}")"
		else no "${t%%:*}" "apt package ${t#*:}"; fi
	done
	if python_ok; then
		ok python3 "$(python3 -V 2>&1)"
	elif [ -e /usr/bin/python3.12 ] && ! /usr/bin/python3.12 -V > /dev/null 2>&1; then
		no python3 "/usr/bin/python3.12 does not run here ($(file -b /usr/bin/python3.12 | cut -d, -f1-2)); the install mode puts the amd64 one back"
	else
		no python3 "apt package python3"
	fi
	if command -v ipsw > /dev/null; then ok ipsw "$(ipsw version 2> /dev/null | grep -m1 -o 'Version: [0-9.]*' || echo present)"
	else no ipsw "blacktop/ipsw $IPSW_VER"; fi
	if command -v apfs-fuse > /dev/null; then ok apfs-fuse "$(command -v apfs-fuse)"
	else no apfs-fuse "sgan81/apfs-fuse, built from source"; fi
	if [ -d /sys/module/nbd ] || modinfo nbd > /dev/null 2>&1; then ok nbd "kernel module"
	else no nbd "WSL's kernel has no nbd module"; fi
	if grep -q hfsplus /proc/filesystems; then ok hfsplus "loaded"
	elif [ -f "$KO" ]; then ok hfsplus "built ($KO), loaded when needed"
	else no hfsplus "no module for $KVER: wsl-build-hfsplus.sh builds it (about 5 GB, 20-60 min)"; fi
	t=$L; [ -d "$t" ] || t=/root
	ok scratch "$L: $(df -h --output=avail "$t" | tail -1 | tr -d ' ') free"
	return $bad
}

install() {
	set -e
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	if ! python_ok && dpkg -l 'python3.12-minimal:arm64' 2> /dev/null | grep -q '^i'; then
		echo "removing the arm64 python3.12-minimal that WSL cannot run"
		dpkg --remove --force-depends python3.12-minimal:arm64
		apt-get install -f -y -qq > /dev/null
	fi
	apt-get install -y -qq $APT_RUN python3.12-minimal:amd64 > /dev/null
	python_ok || { echo "python3 still does not run: see 'apt-get install --reinstall python3'"; exit 1; }
	if ! command -v ipsw > /dev/null; then
		t=$(mktemp -d)
		curl -fsSL -o "$t/ipsw.tar.gz" "$IPSW_URL"
		echo "$IPSW_SHA256  $t/ipsw.tar.gz" | sha256sum -c -
		tar xzf "$t/ipsw.tar.gz" -C "$t"
		install -m 755 "$(find "$t" -type f -name ipsw | head -1)" /usr/local/bin/ipsw
		rm -rf "${t:?}"
	fi
	if ! command -v apfs-fuse > /dev/null; then
		apt-get install -y -qq $APT_BUILD > /dev/null
		s=/opt/src/apfs-fuse
		[ -d $s/.git ] || git clone -q $APFS_FUSE_URL $s
		git -C $s checkout -q $APFS_FUSE_COMMIT
		git -C $s submodule update -q --init
		cmake -S $s -B $s/build -DUSE_FUSE3=ON -DCMAKE_BUILD_TYPE=Release > /dev/null
		make -C $s/build -j"$(nproc)" apfs-fuse > /dev/null
		install -m 755 $s/build/apfs-fuse /usr/local/bin/apfs-fuse
	fi
	bash "$HERE/wsl-build-hfsplus.sh"
	set +e
	check
}

case "${1:-}" in
	check) check ;;
	install) install ;;
	*) echo "usage: wsl-setup.sh check|install"; exit 2 ;;
esac
