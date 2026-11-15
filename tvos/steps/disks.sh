# The disk a start boots: tvos/tv.qcow2, the user's own overlay on the booted roott-b.qcow2 (which a start never
# writes), after the crash folder is emptied of what the install's boots left.
disk_tools
in_root tvos/roott-b.qcow2 <<'EOF'
find $R/private/var/mobile/Library/Logs/CrashReporter -maxdepth 1 -name '*.ips' -delete 2> /dev/null || true
EOF
overlay roott-b.qcow2 tvos/tv.qcow2
