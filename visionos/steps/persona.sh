# After the first boot wrote persona.kb, usersession.kb and the system containers: the mobile user's personas in
# the manifest (HFS+ has no RENAME_SWAP; lsd, installd and pkd need them), MobileGestalt recomputed,
# root26-prefs.py again for mobileactivationd's data ark, then visionOS's own prefs: RealityKeyboard's
# slide-to-type introduction off (its video comes back nil and throws every 13 s), the environments' first-use
# gates (one tap selects a place), VirtualAudio's ProductID 10012 (the only xros routing with a speaker route).
disk_tools
in_root visionos/rootv-b.qcow2 <<'EOF'
ls -l $R/private/var/keybags
python3 -I $S/root26-persona.py $R on
python3 -I $S/root26-mgcache.py $R reset
out=$(python3 -I $S/root26-prefs.py $R)
echo "$out"
case $'\n'$out in
*$'\n''data ark /'*) ;;
*) echo 'no mobileactivationd container on visionos/rootv-b.qcow2: the first boot did not get that far (run -From firstboot)'; exit 1;;
esac
python3 -I $S/rootx-keys.py $R
python3 -I $S/rootx-envfirst.py $R
python3 -I $S/rootx-audioprod.py $R 10012
find $R/private/var/mobile/Library/Logs/CrashReporter -maxdepth 1 -name '*.ips' -delete 2> /dev/null || true
EOF
