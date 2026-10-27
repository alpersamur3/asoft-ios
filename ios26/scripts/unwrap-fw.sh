#!/bin/bash
# Unwrap the cloudOS 26.4b IM4Ps M1 boots (SPTM, TXM, kernelcache, DT) into fw.
set -e
A=${ASOFT26:?set ASOFT26 to the build folder as WSL sees it, e.g. /mnt/d/ios26}
cd "$A"
X=cloudos
F=fw
mkdir -p $F
ipsw img4 im4p extract $X/Firmware/sptm.vresearch1.release.im4p -o $F/sptm 2>&1 | tail -1
ipsw img4 im4p extract $X/Firmware/txm.iphoneos.research.im4p -o $F/txm 2>&1 | tail -1
cp cloud/kernelcache.research.vphone600.decompressed $F/bootkc
cp cloud/vphone600ap.adt $F/dtree.orig
ls -l $F
file $F/* 2>/dev/null || true
