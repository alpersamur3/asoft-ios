# Sourced by the disk scripts (mk-root26.sh, mk-root26g.sh, root26-do.sh, m2-finish.sh, mk-rootx.sh,
# mk-rootw.sh, mk-roott.sh): settling an HFS+ volume with fsck.hfsplus, and nbd devices that are really free.

# hfs_settle DEV [ROUNDS]: repair DEV (unmounted) until a read-only check is clean, one log line per
# round. Linux's hfsplus writes past the journal, so a first pass finds work; but one -y pass has
# been seen to report "repaired successfully" while the next check still found orphaned blocks in
# the bitmap (8 of 9 installs on one PC), so: flush the block device's cache around every pass, so
# each fsck reads what the previous one wrote, and repeat. Returns 1 if the last check is not clean.
hfs_settle() {
	local dev=$1 max=${2:-4} round log
	log=$(mktemp /tmp/hfs-settle.XXXXXX)
	# a loop device reads and writes through its backing device's cache: flush that too
	local back
	back=$(losetup -nO BACK-FILE "$dev" 2> /dev/null || true)
	[ -b "$back" ] || back=
	for ((round = 1; round <= max; round++)); do
		sync
		blockdev --flushbufs $back "$dev" 2> /dev/null || true
		fsck.hfsplus -f -y "$dev" 2>&1 | grep -v 'Illegal name' | tail -2 > "$log" || true
		sync
		blockdev --flushbufs $back "$dev" 2> /dev/null || true
		if fsck.hfsplus -f -n "$dev" > "$log.n" 2>&1; then
			echo "fsck $dev: round $round/$max, clean"
			rm -f "$log" "$log.n"
			return 0
		fi
		echo "fsck $dev: round $round/$max, not clean yet: $(tail -2 "$log.n" | tr '\n' ' ')"
	done
	echo "fsck $dev: still not clean after $max rounds (last repair: $(tr '\n' ' ' < "$log"))"
	rm -f "$log" "$log.n"
	return 1
}

# nbd_wait_free DEV [SECONDS]: wait until DEV has no qemu-nbd behind it (a disconnect is not done
# when qemu-nbd -d returns), 0 when free
nbd_wait_free() {
	local pid=/sys/block/${1#/dev/}/pid i
	for ((i = 0; i < ${2:-20}; i++)); do
		[ -s "$pid" ] || return 0
		sleep 1
	done
	[ ! -s "$pid" ]
}

# nbd_detach DEV: qemu-nbd -d, and wait for the device to be free, so that the next script finds it so
nbd_detach() {
	qemu-nbd -d "$1" > /dev/null 2>&1 || true
	nbd_wait_free "$1" 20 || echo "$1 is still busy after the disconnect (a WSL service may hold a copy of its mount: wsl --terminate frees it)"
}

# nbd_first_free: the first free /dev/nbd12..15 (the scripts leave 0-11 alone), else /dev/nbd12
nbd_first_free() {
	local n
	for n in 12 13 14 15; do
		if [ -b /dev/nbd$n ] && [ ! -s /sys/block/nbd$n/pid ]; then echo /dev/nbd$n; return; fi
	done
	echo /dev/nbd12
}
