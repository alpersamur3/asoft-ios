"""visionOS churn cut, after ios26/scripts/root26-churn.py: drop the launchd jobs that burn the TCG guest's CPU without
doing anything for us. Measured (VISIONOS.md §11, 63 s idle, ltop): of 131 CPU-s, dasd 21.0, mobileassetd 8.6,
contextstored 7.5, PerfPowerServices 4.5, triald 3.0, coreduetd 1.1, biomed 0.5, analyticsd 0.5; crash loops in 28 min:
fileindexerd 17, DumpPanic 8, localizationswitcherd 6, duetexpertd 6, ScreenTimeAgent 6, dmd 5 (each one a relaunch and
a ReportCrash run). Keeps mobileassetd (the environments' assets come through it), wakeboardd, backboardd, SurfBoard,
RunningBoard, lsd, configd, usermanagerd, containermanagerd, locationd, ReportCrash. Reversible: launchd.plist.prechurn.
    rootx-churn.py MOUNTED_ROOT on|off
"""
import os, plistlib, shutil, sys

REMOVE = {
    # the iOS 26 list (root26-churn.py)
    'com.apple.dmd',
    'com.apple.jetpackassetd',
    'com.apple.ScreenTimeAgent',
    'com.apple.ScreenTimeSettingsAgent',
    'com.apple.appprotectiond',
    'com.apple.contextstored',
    'com.apple.duetexpertd',
    'com.apple.installcoordinationd',
    'com.apple.installcoordination_proxy',
    'com.apple.assistantd',
    'com.apple.assistant_cdmd',
    'com.apple.biomed',
    'com.apple.biomesyncd',
    'com.apple.triald',
    'com.apple.DumpPanic',
    'com.apple.amsengagementd',
    'com.apple.mediaanalysisd',
    'com.apple.photoanalysisd',
    'com.apple.dasd',
    # visionOS additions (measured here)
    'com.apple.localizationswitcherd',   # SIGABRT every ~3 min
    'com.apple.fileindexerd',            # fatalError under launchd, 17 reports in 28 min (§9)
    'com.apple.PerfPowerServices',       # 4.5 s of 63; power telemetry
    'com.apple.coreduetd',
    'com.apple.analyticsd',
}


def main():
    root, mode = sys.argv[1], sys.argv[2]
    path = os.path.join(root, 'System/Library/xpc/launchd.plist')
    pre = path + '.prechurn'
    st = os.stat(path)
    if mode == 'on':
        if not os.path.exists(pre):
            shutil.copy2(path, pre)
        src = pre
    elif mode == 'off':
        if not os.path.exists(pre):
            sys.exit('no .prechurn backup to restore')
        shutil.copy2(pre, path)
        print('restored launchd.plist from .prechurn')
        return
    else:
        sys.exit(__doc__)
    with open(src, 'rb') as f:
        plist = plistlib.load(f)
    jobs = plist['LaunchDaemons']
    removed = sorted(j.get('Label') for j in jobs.values() if j.get('Label') in REMOVE)
    for k in [k for k, j in jobs.items() if j.get('Label') in REMOVE]:
        del jobs[k]
    with open(path, 'wb') as f:
        plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, st.st_uid, st.st_gid)
    os.chmod(path, st.st_mode & 0o7777)
    print('removed %d jobs: %s' % (len(removed), removed))
    print('not found: %s' % sorted(REMOVE - set(removed)))
    print('remaining LaunchDaemons: %d' % len(jobs))


if __name__ == '__main__':
    main()
