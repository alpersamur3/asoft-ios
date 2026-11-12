# tvOS's copy of the guest GPU driver in $W/gpu (the patches step puts it on the root, the trust cache takes its
# hashes.txt): both Mach-Os retargeted to tvOS (platform 3, platt.py; dyld refuses an iOS one) and ad-hoc signed.
# On the hand-built disk this gave the CDHashes 7d928a3b... (the driver) and b8ece21a... (the compiler plugin).
N=$W/gpu.new G=$W/gpu.new/{BUNDLE}
rm -rf "$N"; mkdir -p "$N"
cp -R "$A/gpu-driver/{BUNDLE}" "$G"
: > "$N/hashes.txt"
for f in "$G"/AppleParavirtGPUMetalIOGPUFamily "$G"/libAppleParavirtCompilerPluginIOGPUFamily.dylib; do
	[ -f "$f" ] || { echo "$f is missing: the GPU driver needs Apple's binary and the compiler plugin"; exit 1; }
	python3 -I $S/platt.py "$f"
	id=$(basename "$f" .dylib); [ "$id" = AppleParavirtGPUMetalIOGPUFamily ] && id=com.apple.driver.$id
	python3 $S/adhoc_sign.py "$f" "$id" | cut -d' ' -f1 | tee -a "$N/hashes.txt"
done
rm -rf "$W/gpu"; mv "$N" "$W/gpu"
