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
  - removes LastSystemVersion from com.apple.migration so DataMigration runs once on the next boot
  - moves the SystemAppMigrator plugin out of /System/Library/DataClassMigrators (see
    skip_system_app_migrator), unless ASOFT_KEEP_SYSTEMAPPMIGRATOR=1
Idempotent.
"""
import os, plistlib, shutil, sys

RESTORE = {'com.apple.installcoordinationd', 'com.apple.installcoordination_proxy', 'com.apple.dasd'}


def skip_system_app_migrator(root):
    """SystemAppMigrator installs the deletable system apps through installcoordinationd, which needs
    an APFS clone: on this HFS+ root every install fails, and the plugin waited ~33 of DataMigration's
    ~52 min on a lock before it "Returned NO" (stackshots of the 2026-11-04 run). apply-apps.sh puts the
    apps into /Applications itself. The other migrators do not name it. It goes to a sibling folder
    datamigrator does not scan; ASOFT_KEEP_SYSTEMAPPMIGRATOR=1 puts it back."""
    d = os.path.join(root, 'System/Library/DataClassMigrators')
    off = os.path.join(root, 'System/Library/DataClassMigrators-off')
    name = 'SystemAppMigrator.migrator'
    if os.environ.get('ASOFT_KEEP_SYSTEMAPPMIGRATOR') == '1':
        if os.path.isdir(os.path.join(off, name)) and not os.path.exists(os.path.join(d, name)):
            shutil.move(os.path.join(off, name), d)
            print('SystemAppMigrator.migrator put back (ASOFT_KEEP_SYSTEMAPPMIGRATOR=1)')
        else:
            print('SystemAppMigrator.migrator stays (ASOFT_KEEP_SYSTEMAPPMIGRATOR=1)')
        return
    if os.path.isdir(os.path.join(d, name)):
        os.makedirs(off, exist_ok=True)
        shutil.rmtree(os.path.join(off, name), ignore_errors=True)
        shutil.move(os.path.join(d, name), off)
        print('SystemAppMigrator.migrator moved to DataClassMigrators-off (it cannot install on HFS+)')
    else:
        print('SystemAppMigrator.migrator: already out')


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
    changed = False
    if m.pop('LastSystemVersion', None) is not None:
        changed = True
        print('com.apple.migration: LastSystemVersion removed, DataMigration runs on next boot')
    else:
        print('com.apple.migration: no LastSystemVersion')
    # datamigrator (runs as mobile) reboots or panics when a plugin outlives its time limit
    # (DMRebootTimer: "Plugin %@ hanging. Panicking!" / "Rebooting!"), unless
    # -[DMEnvironment shouldWatchdogPluginsAfterTimeout] says NO, which it does only when this key
    # is present and false (no internal-build check, iOS 26.6 23G90). On a slow host SpringBoard.migrator
    # (SplashBoard's launch images for every app, ~10 min on a 13700HX) outlives the limit: the S25
    # panicked at 59 min, then rebooted at 50 min and stayed on the logo (2026-11-09).
    if m.get('DMWatchdogPluginsAfterTimeout') is not False:
        m['DMWatchdogPluginsAfterTimeout'] = False
        changed = True
        print('com.apple.migration: DMWatchdogPluginsAfterTimeout = false (no plugin watchdog, no reboot timer)')
    skip_system_app_migrator(root)
    if changed:
        st = os.stat(mig)
        with open(mig, 'wb') as f:
            plistlib.dump(m, f, fmt=plistlib.FMT_BINARY)
        os.chown(mig, st.st_uid, st.st_gid)
        os.chmod(mig, st.st_mode & 0o7777)


if __name__ == '__main__':
    main()
