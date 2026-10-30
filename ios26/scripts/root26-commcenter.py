#!/usr/bin/env python3
"""Puts CommCenter's jobs back into launchd.plist on a disk built before 2026-10-30, whose
root26-tweaks.py removed them, from the launchd.plist.orig it kept. Run as root on the mounted root:

  root26-do.sh DISK.qcow2 'python3 SCRIPTS/root26-commcenter.py $R'

Without CommCenter SpringBoard reconnects to it every second and resets the idle timer each time:
the display never sleeps, the Lock Screen is drawn at ~50 frames a second for ever (a quarter of the
guest's CPU) and the side button seems dead. launchd picks com.apple.CommCenter-noncellular on a
device tree without a baseband. Idempotent.
"""
import os, plistlib, sys


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = os.path.join(sys.argv[1], 'System/Library/xpc/launchd.plist')
    st = os.stat(path)
    with open(path + '.orig', 'rb') as f:
        orig = plistlib.load(f)['LaunchDaemons']
    with open(path, 'rb') as f:
        plist = plistlib.load(f)
    back = {k: j for k, j in orig.items() if j.get('Label') == 'com.apple.CommCenter'}
    plist['LaunchDaemons'].update(back)
    with open(path, 'wb') as f:
        plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, st.st_uid, st.st_gid)
    os.chmod(path, st.st_mode & 0o7777)
    print('CommCenter jobs in launchd.plist:', sorted(back))


if __name__ == '__main__':
    main()
