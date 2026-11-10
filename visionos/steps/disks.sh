# The two disks a start boots, on the booted rootv-b.qcow2 (the silent state: root26-prefs.py moved
# VirtualAudio.plugin to HAL.disabled):
#   rootv-s.qcow2  silent: VirtualAudio stays out (audiomxd takes about one vCPU with it) + churn3
#   rootv-a.qcow2  sound (only with the audio plug-in): VirtualAudio back in HAL, for virtio-snd
# and on each the user's own overlay, vision-silent.qcow2 / vision.qcow2, which a start writes.
# First the Accessibility Shortcut off on rootv-b (three crown presses turned VoiceOver on).
disk_tools
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
if [ -n '{AUDIO}' ]; then
	overlay rootv-b.qcow2 visionos/rootv-a.qcow2
	in_root visionos/rootv-a.qcow2 <<'EOF'
python3 -I $S/rootx-va.py $R on
echo "HAL plug-ins: $(ls $R/System/Library/Audio/Plug-Ins/HAL $R/Library/Audio/Plug-Ins/HAL | grep -E '\.(driver|plugin)$' | tr '\n' ' ')"
EOF
	overlay rootv-a.qcow2 visionos/vision.qcow2
else
	echo 'no audio plug-in: no sound disk (visionos/vision.qcow2); visionOS starts silent'
fi
