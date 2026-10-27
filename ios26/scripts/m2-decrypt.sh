#!/bin/bash
# Decrypt the iPhone OS image (AEA; key from Apple's key service, as for the
# SystemOS cryptex in M0) into os, then report the image and its tree size.
set -eu
A=${ASOFT26:?set ASOFT26 to the build folder as WSL sees it, e.g. /mnt/d/ios26}
cd "$A/iphone"
mkdir -p ../os
ipsw fw aea --info 094-97246-090.dmg.aea 2>&1 | head -20
time ipsw fw aea 094-97246-090.dmg.aea -o ../os 2>&1 | tail -5
ls -l ../os
