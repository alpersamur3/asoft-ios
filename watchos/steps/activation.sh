# A quick boot state saved on the disk (Start-watchOS.ps1's asoft-quick) holds the disk as it was then:
# resumed after this, it would undo this write. It stays as a way back, which a start does not resume by
# itself: watchos/watch.qcow2.quick-used names it (its id and time, as Start-watchOS.ps1 writes them).
# Going back to it later undoes this step's write too.
if command -v qemu-img > /dev/null && command -v python3 > /dev/null; then
	key=$(qemu-img info --output=json -U watchos/watch.qcow2 | python3 -c 'import json, sys
for s in json.load(sys.stdin).get("snapshots", []):
    if s["name"] == "asoft-quick": print(s["id"], s["date-sec"], s["date-nsec"])' || true)
	if [ -n "$key" ]; then
		echo "$key" > watchos/watch.qcow2.quick-used
		echo 'the quick boot state on watchos/watch.qcow2 stays as a way back; a start no longer resumes it'
	fi
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
