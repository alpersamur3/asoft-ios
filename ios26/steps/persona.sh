disk_tools
in_root root26g.qcow2 <<'EOF'
ls -l $R/private/var/keybags
python3 -I $S/root26-persona.py $R on
python3 -I $S/root26-mgcache.py $R reset
python3 -I $S/root26-prefs.py $R
EOF
