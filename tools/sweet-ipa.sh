#!/bin/bash
# Offline .ipa installation for SWEET (run as root in WSL/Linux, with iOS shut down):
#
#   sweet-ipa.sh setup DISK.qcow2 SWEETINSTALLD   install the sweetinstalld daemon (apps/sweetinstalld)
#   sweet-ipa.sh add   DISK.qcow2 FILE.ipa...      drop .ipa files into its inbox
#   sweet-ipa.sh list  DISK.qcow2                  inbox, installed and failed .ipa files with their logs
#
# At the next boot sweetinstalld installs every inbox .ipa through installd and
# logs to the console ("sweetinstalld: ..." in serial.txt). setup puts the daemon
# at /usr/libexec/sweetinstalld and adds its job to launchd's job cache,
# /System/Library/xpc/launchd.plist (read from disk with boot-arg
# launchd_unsecure_cache=1; the original is kept as launchd.plist.sweet-orig).
#
# DISK is written through Linux's hfsplus driver, which ignores the journal: a
# volume whose journal still holds transactions (iOS was not shut down cleanly)
# gets them replayed first with fsck.hfsplus. Use an overlay, not the base image.
set -euo pipefail
cmd=${1:-}; disk=${2:-}
[ -n "$cmd" ] && [ -f "$disk" ] || { sed -n '2,7p' "$0"; exit 2; }
shift 2
MNT=/mnt/sweet-ipa
DEV=/dev/nbd2
ROOT=/private/var/mobile/Media/Sweet
JOB=com.sweet.installd

grep -q hfsplus /proc/filesystems || modprobe hfsplus 2>/dev/null ||
    { echo "no hfsplus driver (WSL: build and load it first)" >&2; exit 1; }
modprobe nbd max_part=8 2>/dev/null || true
mkdir -p $MNT
ro=; [ "$cmd" = list ] && ro=--read-only
qemu-nbd $ro --connect=$DEV "$disk"
trap 'mountpoint -q $MNT && umount $MNT; qemu-nbd --disconnect $DEV >/dev/null' EXIT
sleep 1

if [ "$cmd" = list ]; then
    mount -t hfsplus -o ro $DEV $MNT
    for d in Inbox Installed Failed; do
        echo "== $d"
        ls -la "$MNT$ROOT/$d" 2>/dev/null | grep -v '^total\|\.$' || true
        cat "$MNT$ROOT/$d"/*.log 2>/dev/null || true
    done
    exit 0
fi

# Clean volume with an empty journal, or replay the journal first.
python3 -I - "$DEV" <<'PY' || fsck.hfsplus -fy $DEV
import struct, sys
f = open(sys.argv[1], 'rb')
f.seek(1024); vh = f.read(512)
attrs, = struct.unpack('>I', vh[4:8])
if not attrs & 0x2000:
    sys.exit(0 if attrs & 0x100 else 1)
jib, bsize = struct.unpack('>I', vh[12:16])[0], struct.unpack('>I', vh[40:44])[0]
f.seek(jib * bsize); off, = struct.unpack('>Q', f.read(52)[36:44])
f.seek(off); jh = f.read(24)
order = '>' if jh[:4] == b'JNLx' else '<'      # the journal header is in its writer's byte order
start, end = struct.unpack(order + 'QQ', jh[8:24])
sys.exit(0 if start == end else 1)
PY
mount -t hfsplus -o rw,force $DEV $MNT

case $cmd in
setup)
    bin=$1
    install -m 755 -o 0 -g 0 "$bin" $MNT/usr/libexec/sweetinstalld
    plist=$MNT/System/Library/xpc/launchd.plist
    [ -f $plist.sweet-orig ] || cp -p $plist $plist.sweet-orig
    python3 -I - $plist $MNT/System/Library/LaunchDaemons/$JOB.plist "$JOB" <<'PY'
import plistlib, sys
cache, job_path, label = sys.argv[1:4]
job = {
    'Label': label,
    'ProgramArguments': ['/usr/libexec/sweetinstalld'],
    'RunAtLoad': True,
    'KeepAlive': True,
    # Without it launchd starts the job as a background process: while iOS boots its
    # xpcproxy got so little CPU that sweetinstalld ran only 2.5-3.5 min after launch.
    'ProcessType': 'Interactive',
    'UserName': 'root',
    'StandardOutPath': '/dev/console',
    'StandardErrorPath': '/dev/console',
}
with open(cache, 'rb') as f:
    plist = plistlib.load(f)
plist['LaunchDaemons']['/System/Library/LaunchDaemons/%s.plist' % label] = job
with open(cache, 'wb') as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
with open(job_path, 'wb') as f:
    plistlib.dump(job, f, fmt=plistlib.FMT_XML)
print('launchd job %s added (%d jobs)' % (label, len(plist['LaunchDaemons'])))
PY
    mkdir -p $MNT$ROOT/Inbox
    chown -R 501:501 $MNT$ROOT
    chmod 0777 $MNT$ROOT/Inbox
    ;;
add)
    mkdir -p $MNT$ROOT/Inbox
    for ipa in "$@"; do
        install -m 644 -o 501 -g 501 "$ipa" "$MNT$ROOT/Inbox/$(basename "$ipa")"
        echo "inbox: $(basename "$ipa")"
    done
    ;;
*)
    echo "unknown command $cmd" >&2; exit 2 ;;
esac
sync
