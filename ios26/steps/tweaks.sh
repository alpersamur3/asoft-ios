disk_tools
in_root root26g.qcow2 <<'EOF'
python3 -I $S/root26-prefs.py $R
python3 -I $S/root26-sb-undiag.py $R
python3 -I $S/root26-bbd-fix.py $R
# the system keybag (4.4.2): a plist with KeyBagKeys = the data "SWEET", root, 0600
install -d -m 0700 -o 0 -g 0 $R/private/var/keybags
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0"><dict><key>KeyBagKeys</key><data>U1dFRVQ=</data></dict></plist>' \
	> $R/private/var/keybags/systembag.kb
chown 0:0 $R/private/var/keybags/systembag.kb
chmod 0600 $R/private/var/keybags/systembag.kb
python3 -I $S/root26-churn.py $R on
python3 -I $S/root26-dbg-off.py $R
python3 -I $S/root26-trim.py $R on
EOF
