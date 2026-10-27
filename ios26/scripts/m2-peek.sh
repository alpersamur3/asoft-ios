#!/bin/bash
# Look inside an APFS image read-only (apfs-fuse): run a command with $M as its root.
#   m2-peek.sh IMAGE 'command using $M'
set -u
IMG=$1
M=/tmp/peek.$$
L=/tmp/peek.$$.dmg
mkdir -p $M
ln -sf "$IMG" $L		# apfs-fuse parses UDIF only for names ending in .dmg
apfs-fuse -o allow_other $L $M || exit 1
[ -d $M/root ] && M=$M/root
export M
bash -c "$2"
cd /
fusermount -u /tmp/peek.$$
rmdir /tmp/peek.$$
rm -f $L
