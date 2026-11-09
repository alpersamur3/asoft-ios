# a quick boot state saved on the disk (Start-watchOS.ps1's asoft-quick) holds the guest's view of the disk
# before this write: resuming it afterwards would undo or corrupt it, so it goes first
if command -v qemu-img > /dev/null && qemu-img snapshot -l watchos/watch.qcow2 | grep -q ' asoft-quick '; then
	qemu-img snapshot -d asoft-quick watchos/watch.qcow2
	echo 'dropped the quick boot state on watchos/watch.qcow2 (the next start boots)'
fi
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
