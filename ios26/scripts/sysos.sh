#!/bin/bash
# Decrypt the iPhone SystemOS cryptex (AEA) and pull the arm64e dyld_shared_cache out of it.
set -e
A=${ASOFT26:?set ASOFT26 to the build folder as WSL sees it, e.g. /mnt/d/ios26}
cd "$A/iphone"
mkdir -p ../os
ipsw fw aea --info 094-95368-092.dmg.aea 2>&1 | head -20
ipsw fw aea 094-95368-092.dmg.aea -o ../os 2>&1 | tail -5
ls -l ../os
