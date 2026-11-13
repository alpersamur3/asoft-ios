# After the first boot wrote persona.kb, usersession.kb and the system containers (the hand-built cmdT2.sh): the
# mobile user's personas in the manifest (HFS+ has no RENAME_SWAP), MobileGestalt recomputed, root26-prefs.py again
# for mobileactivationd's data ark, roott-prefs.py again (screen saver and idle screen off: after 5 idle minutes
# PineBoard put a black IdleScreen up on the hand-built disk), the crash folder emptied.
disk_tools
in_root tvos/roott-b.qcow2 <<'EOF'
ls -l $R/private/var/keybags
python3 -I $S/root26-persona.py $R on
python3 -I $S/root26-mgcache.py $R reset
out=$(python3 -I $S/root26-prefs.py $R)
echo "$out"
case $'\n'$out in
*$'\n''data ark /'*) ;;
*) echo 'no mobileactivationd container on tvos/roott-b.qcow2: the first boot did not get that far (run -From firstboot)'; exit 1;;
esac
python3 -I $S/roott-prefs.py $R
find $R/private/var/mobile/Library/Logs/CrashReporter -maxdepth 1 -name '*.ips' -delete 2> /dev/null || true
EOF
