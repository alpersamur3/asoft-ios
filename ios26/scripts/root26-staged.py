#!/usr/bin/env python3
"""Get iOS 26's deletable system apps installed on a root disk that left them out.

  root26-staged.py MOUNTED_ROOT

mk-root26.sh left /private/var/staged_system_apps empty (space), and the churn
cut (root26-churn.py) removed installcoordinationd, so the SystemAppMigrator
data migrator found nothing to install and marked system app migration done.
After the apps are copied back (apply-staged.sh), this:
  - puts installcoordinationd, installcoordination_proxy and dasd back into
    launchd.plist from the .prechurn copy (everything else the churn cut
    removed stays out); dasd runs SpringBoard's poster update tasks
  - removes LastSystemVersion from com.apple.migration so DataMigration (and
    with it SystemAppMigrator) runs once on the next boot.
Idempotent.
"""
import os, plistlib, sys

RESTORE = {'com.apple.installcoordinationd', 'com.apple.installcoordination_proxy', 'com.apple.dasd'}


def main():
    root = sys.argv[1]
    path = os.path.join(root, 'System/Library/xpc/launchd.plist')
    with open(path + '.prechurn', 'rb') as f:
        pre = plistlib.load(f)['LaunchDaemons']
    with open(path, 'rb') as f:
        plist = plistlib.load(f)
    jobs = plist['LaunchDaemons']
    added = []
    for key, job in pre.items():
        if job.get('Label') in RESTORE and key not in jobs:
            jobs[key] = job
            added.append(job['Label'])
    st = os.stat(path)
    with open(path, 'wb') as f:
        plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, st.st_uid, st.st_gid)
    os.chmod(path, st.st_mode & 0o7777)
    print('launchd.plist: restored', sorted(added) or 'nothing (already there)')

    mig = os.path.join(root, 'private/var/mobile/Library/Preferences/com.apple.migration.plist')
    with open(mig, 'rb') as f:
        m = plistlib.load(f)
    if m.pop('LastSystemVersion', None) is not None:
        st = os.stat(mig)
        with open(mig, 'wb') as f:
            plistlib.dump(m, f, fmt=plistlib.FMT_BINARY)
        os.chown(mig, st.st_uid, st.st_gid)
        print('com.apple.migration: LastSystemVersion removed, DataMigration runs on next boot')
    else:
        print('com.apple.migration: no LastSystemVersion')


if __name__ == '__main__':
    main()
