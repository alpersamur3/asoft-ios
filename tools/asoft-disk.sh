#!/bin/bash
# Offline changes to an iOS disk image (run as root in WSL/Linux, with iOS shut down):
#
#   asoft-disk.sh installer DISK.qcow2 ASOFTINSTALLD  install the asoftinstalld daemon (apps/asoftinstalld)
#   asoft-disk.sh add       DISK.qcow2 FILE.ipa...    drop .ipa files into its inbox
#   asoft-disk.sh list      DISK.qcow2                inbox, installed and failed .ipa files with their logs
#   asoft-disk.sh name      DISK.qcow2 "NAME"         the device name (Settings > General > About > Name)
#   asoft-disk.sh nodim     DISK.qcow2                no lock screen dimming or auto-lock (always on power)
#
# DISK may also be the directory where an iOS root is mounted read-write (the ASoftware
# helper VM, which has it mounted already).
#
# At the next boot asoftinstalld installs every inbox .ipa through installd and
# logs to the console ("asoftinstalld: ..." in serial.txt). installer puts the daemon
# at /usr/libexec/asoftinstalld and adds its job to launchd's job cache,
# /System/Library/xpc/launchd.plist (read from disk with boot-arg
# launchd_unsecure_cache=1; the original is kept as launchd.plist.sweet-orig). It
# replaces the earlier sweetinstalld (com.sweet.installd) if that is there.
#
# DISK is written through Linux's hfsplus driver, which ignores the journal: a
# volume whose journal still holds transactions (iOS was not shut down cleanly)
# gets them replayed first with fsck.hfsplus. Use an overlay, not the base image,
# and never one that another overlay sits on.
#
# Copyright (c) 2026 ASoftware. MIT License, see LICENSE.
set -euo pipefail
cmd=${1:-}; disk=${2:-}
[ -n "$cmd" ] && { [ -f "$disk" ] || [ -d "$disk" ]; } || { sed -n '2,12p' "$0"; exit 2; }
shift 2
MNT=/mnt/asoft-disk
DEV=/dev/nbd2
ROOT=/private/var/mobile/Media/ASoftware
OLD_ROOT=/private/var/mobile/Media/Sweet
JOB=com.asoftware.installd
OLD_JOB=com.sweet.installd

if [ -d "$disk" ]; then
    MNT=$(realpath "$disk")
    [ -d "$MNT/System/Library/xpc" ] || { echo "$disk: not an iOS root" >&2; exit 2; }
else
    # qcow2 only: anything else (a mistyped argument) would be attached as a raw disk
    [ "$(head -c 4 "$disk" | od -An -tx1 | tr -d ' \n')" = 514649fb ] || { echo "$disk: not a qcow2 image" >&2; exit 2; }
    grep -q hfsplus /proc/filesystems || modprobe hfsplus 2>/dev/null ||
        { echo "no hfsplus driver (WSL: build and load it first)" >&2; exit 1; }
    modprobe nbd max_part=8 2>/dev/null || true
    mkdir -p $MNT
    ro=; [ "$cmd" = list ] && ro=--read-only
    # The quick boot's saved state (qemu/patches/0009) holds the disk as it was then: written
    # now, the disk would no longer match it
    if [ -z "$ro" ] && qemu-img snapshot -l "$disk" | grep -qw asoft-quick; then
        qemu-img snapshot -d asoft-quick "$disk" && echo "dropped the quick boot state"
    fi
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
fi

case $cmd in
installer)
    bin=$1
    install -m 755 -o 0 -g 0 "$bin" $MNT/usr/libexec/asoftinstalld
    rm -f $MNT/usr/libexec/sweetinstalld $MNT/System/Library/LaunchDaemons/$OLD_JOB.plist
    plist=$MNT/System/Library/xpc/launchd.plist
    [ -f $plist.sweet-orig ] || cp -p $plist $plist.sweet-orig
    python3 -I - $plist $MNT/System/Library/LaunchDaemons/$JOB.plist "$JOB" "$OLD_JOB" <<'PY'
import plistlib, sys
cache, job_path, label, old_label = sys.argv[1:5]
job = {
    'Label': label,
    'ProgramArguments': ['/usr/libexec/asoftinstalld'],
    'RunAtLoad': True,
    'KeepAlive': True,
    # Without it launchd starts the job as a background process: while iOS boots its
    # xpcproxy got so little CPU that the daemon ran only 2.5-3.5 min after launch.
    'ProcessType': 'Interactive',
    'UserName': 'root',
    'StandardOutPath': '/dev/console',
    'StandardErrorPath': '/dev/console',
}
with open(cache, 'rb') as f:
    plist = plistlib.load(f)
daemons = plist['LaunchDaemons']
daemons.pop('/System/Library/LaunchDaemons/%s.plist' % old_label, None)
daemons['/System/Library/LaunchDaemons/%s.plist' % label] = job
with open(cache, 'wb') as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
with open(job_path, 'wb') as f:
    plistlib.dump(job, f, fmt=plistlib.FMT_XML)
print('launchd job %s added (%d jobs)' % (label, len(daemons)))
PY
    if [ -d $MNT$OLD_ROOT ] && [ ! -e $MNT$ROOT ]; then
        mv $MNT$OLD_ROOT $MNT$ROOT
    fi
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
name)
    # configd's preferences: ComputerName is what iOS shows as the device name; the host
    # names (Bonjour, DHCP) get the same name without spaces. A root that has not booted
    # yet has no preferences.plist: configd adds the rest to the one made here.
    python3 -I - $MNT/private/var/preferences/SystemConfiguration/preferences.plist "$1" <<'PY'
import os, plistlib, re, sys
path, name = sys.argv[1:3]
if os.path.exists(path):
    with open(path, 'rb') as f:
        raw = f.read()
else:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    raw = plistlib.dumps({}, fmt=plistlib.FMT_BINARY)
prefs = plistlib.loads(raw)
fmt = plistlib.FMT_BINARY if raw.startswith(b'bplist') else plistlib.FMT_XML
host = re.sub(r'[^A-Za-z0-9-]+', '-', name).strip('-') or 'iPhone'
system = prefs.setdefault('System', {})
system.setdefault('System', {}).update({'ComputerName': name, 'ComputerNameEncoding': 0x8000100, 'HostName': host})
system.setdefault('Network', {}).setdefault('HostNames', {})['LocalHostName'] = host
with open(path, 'wb') as f:
    plistlib.dump(prefs, f, fmt=fmt)
print('device name: %s (host %s)' % (name, host))
PY
    ;;
nodim)
    # SpringBoard dims the lock screen and asks for the display off seconds after boot. The
    # kernel keeps the display on (sweetfb_keepon), so the dimmed last frame stayed until a
    # key woke iOS. Never dim or lock while on power (the emulated battery always charges).
    python3 -I - $MNT/private/var/mobile/Library/Preferences/com.apple.springboard.plist <<'PY'
import os, plistlib, sys
path = sys.argv[1]
prefs = {}
if os.path.exists(path):
    with open(path, 'rb') as f:
        prefs = plistlib.load(f)
prefs.update({'SBDontDimOrLockOnAC': True, 'SBDisableAutoDim': True})
with open(path, 'wb') as f:
    plistlib.dump(prefs, f, fmt=plistlib.FMT_BINARY)
os.chown(path, 501, 501)
print('SpringBoard: no dimming or auto-lock on power')
PY
    ;;
*)
    echo "unknown command $cmd" >&2; exit 2 ;;
esac
sync
