"""tvOS churn cut, after ios26/scripts/root26-churn.py and visionos/scripts/rootx-churn.py: launchd jobs that only
crash and restart here are taken out of the root's launchd.plist. Measured on 24K122 (2026-11-15, two boots of an
installed disk): DumpPanic ends with EXC_BREAKPOINT every two minutes for as long as tvOS runs, each time with a
ReportCrash run and one more .ips on the user disk; there is no panic to dump on this machine. Nothing else is cut:
the CPU users of the iOS 26 and visionOS lists (dasd, triald, biomed ...) have not been measured on tvOS.
Works on launchd.plist as roott-jobs.py left it. Reversible: launchd.plist.prechurn.

    roott-churn.py MOUNTED_ROOT on|off
"""
import os
import plistlib
import shutil
import sys

REMOVE = {
    'com.apple.DumpPanic',
}


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ('on', 'off'):
        sys.exit(__doc__)
    root, mode = sys.argv[1], sys.argv[2]
    path = os.path.join(root, 'System/Library/xpc/launchd.plist')
    pre = path + '.prechurn'
    st = os.stat(path)
    if mode == 'off':
        if not os.path.exists(pre):
            sys.exit('no .prechurn backup to restore')
        shutil.copy2(pre, path)
        os.chown(path, st.st_uid, st.st_gid)
        print('restored launchd.plist from .prechurn')
        return
    if not os.path.exists(pre):
        shutil.copy2(path, pre)
        os.chown(pre, st.st_uid, st.st_gid)
    with open(pre, 'rb') as f:
        plist = plistlib.load(f)
    jobs = plist['LaunchDaemons']
    removed = sorted(j.get('Label') for j in jobs.values() if j.get('Label') in REMOVE)
    for k in [k for k, j in jobs.items() if j.get('Label') in REMOVE]:
        del jobs[k]
    with open(path, 'wb') as f:
        plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, st.st_uid, st.st_gid)
    os.chmod(path, st.st_mode & 0o7777)
    print('removed %d job(s): %s' % (len(removed), ', '.join(removed) or 'none'))
    missing = sorted(REMOVE - set(removed))
    if missing:
        print('not in this root\'s launchd.plist (another tvOS build?): %s' % ', '.join(missing))
    print('remaining LaunchDaemons: %d' % len(jobs))


if __name__ == '__main__':
    main()
