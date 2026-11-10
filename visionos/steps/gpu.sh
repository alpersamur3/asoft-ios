N=$W/gpu.new G=$W/gpu.new/{BUNDLE}
rm -rf "$N"; mkdir -p "$N"
cp -R "$A/gpu-driver/{BUNDLE}" "$G"
: > "$N/hashes.txt"
for f in "$G"/AppleParavirtGPUMetalIOGPUFamily "$G"/libAppleParavirtCompilerPluginIOGPUFamily.dylib; do
	[ -f "$f" ] || { echo "$f is missing: the GPU driver needs Apple's binary and the compiler plugin"; exit 1; }
	python3 -I $S/platx.py "$f"
	id=$(basename "$f" .dylib); [ "$id" = AppleParavirtGPUMetalIOGPUFamily ] && id=com.apple.driver.$id
	python3 $S/adhoc_sign.py "$f" "$id" | cut -d' ' -f1 | tee -a "$N/hashes.txt"
done
rm -rf "$W/gpu"; mv "$N" "$W/gpu"
