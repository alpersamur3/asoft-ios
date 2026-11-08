disk_tools
in_root root26-apps.qcow2 <<'EOF'
bash $S/apply-apps.sh
python3 -I $S/root26-nowatchdog.py $R
python3 -I $S/root26-aod.py $R
EOF
