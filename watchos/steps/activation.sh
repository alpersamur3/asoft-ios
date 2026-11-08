disk_tools
in_root watchos/watch.qcow2 <<'EOF'
out=$(python3 -I $S/root26-prefs.py $R)
echo "$out"
case $'\n'$out in
*$'\n''data ark /'*) ;;
*) echo 'no mobileactivationd container on watchos/watch.qcow2: the first boot did not get that far (run -From firstboot)'; exit 1;;
esac
find $R/private/var/mobile/Library/Logs/CrashReporter -maxdepth 1 -name '*.ips' -delete 2> /dev/null || true
EOF
