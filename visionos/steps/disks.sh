# The two disks a start boots, on the booted rootv-b.qcow2 (the silent state: root26-prefs.py moved
# VirtualAudio.plugin to HAL.disabled):
#   rootv-s.qcow2  silent: VirtualAudio stays out (audiomxd takes about one vCPU with it) + churn3
#   rootv-a.qcow2  sound (only with the audio plug-in): VirtualAudio back in HAL, for virtio-snd
# and on each the user's own overlay, vision-silent.qcow2 / vision.qcow2, which a start writes.
# First the Accessibility Shortcut off on rootv-b (three crown presses turned VoiceOver on).
# When the installer only adds the sound disk (a finished silent install that the plug-in reached later), only the
# sound branch is made, on the finished rootv-b: rootv-b, rootv-s and vision-silent.qcow2 are not written.
disk_tools
if [ -z '{SOUND_ONLY}' ]; then
	in_root visionos/rootv-b.qcow2 <<'EOF'
python3 -I $S/a11y-off.py $R
find $R/private/var/mobile/Library/Logs/CrashReporter -maxdepth 1 -name '*.ips' -delete 2> /dev/null || true
EOF
	rm -f "$W/rootv-s.qcow2" "$W/rootv-a.qcow2"
	overlay rootv-b.qcow2 visionos/rootv-s.qcow2
	in_root visionos/rootv-s.qcow2 <<'EOF'
python3 -I $S/rootx-va.py $R off
python3 -I $S/rootx-churn3.py $R
EOF
	overlay rootv-s.qcow2 visionos/vision-silent.qcow2
else
	echo 'the silent disk is finished: it and the layers under it stay as they are; only the sound disk is made'
fi
if [ -n '{AUDIO}' ]; then
	overlay rootv-b.qcow2 visionos/rootv-a.qcow2
	# a root patched without the plug-in (it came after the patches step) gets it here, on the sound layer only, as
	# rootx-patch.sh puts it on rootv-p: VPhoneVirtIOSound.driver and the AID0 -> AID10001 tunings link
	in_root visionos/rootv-a.qcow2 <<'EOF'
AUDIO='{AUDIO}' H=$R/System/Library/Audio/Plug-Ins/HAL T=$R/Library/Audio/Tunings
V=$H/VPhoneVirtIOSound.driver
if [ ! -f $V/VPhoneVirtIOSound ]; then
	[ -d $H ] || { echo "no HAL plug-in folder on the root"; exit 1; }
	[ -d $T/AID10001 ] || { echo "no $T/AID10001 on the root"; exit 1; }
	rm -rf "${V:?}"; mkdir -p $V/_CodeSignature
	for f in VPhoneVirtIOSound Info.plist _CodeSignature/CodeResources; do cat "$AUDIO/$f" > "$V/$f"; cmp "$AUDIO/$f" "$V/$f"; done
	chown -R 0:0 $V; chmod 755 $V $V/_CodeSignature $V/VPhoneVirtIOSound; chmod 644 $V/Info.plist $V/_CodeSignature/CodeResources
	ln -sfn AID10001 $T/AID0
	echo "VPhoneVirtIOSound.driver and AID0 -> AID10001 on the sound layer (the root under it has no plug-in)"
fi
python3 -I $S/rootx-va.py $R on
echo "HAL plug-ins: $(ls $R/System/Library/Audio/Plug-Ins/HAL $R/Library/Audio/Plug-Ins/HAL | grep -E '\.(driver|plugin)$' | tr '\n' ' ')"
EOF
	overlay rootv-a.qcow2 visionos/vision.qcow2
else
	echo 'no audio plug-in: no sound disk (visionos/vision.qcow2); visionOS starts silent'
fi
