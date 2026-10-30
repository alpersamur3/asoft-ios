#!/usr/bin/env python3
"""M2 churn-cut: disable crash-looping / heavy non-essential launchd jobs on the
iOS 26 root so SpringBoard isn't starved out of the crowded pri-31 band (measured:
380 threads at pri 31, SpringBoard gets ~71us CPU). Reversible: backs up launchd.plist to launchd.plist.prechurn.
Keeps lsd, configd, runningboardd, usermanagerd, containermanagerd, locationd,
ReportCrash, backboardd, SpringBoard. Run as root on the mounted HFS+ root:

  root26-churn.py MOUNTED_ROOT on|off

Idempotent.
"""
import os, plistlib, shutil, sys

REMOVE = {
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
    # Measured 2026-10-30 (notes: IOS26-BOOT-SERVICES): DumpPanic crashes every 2 min for ever
    # (RunAtLoad, KeepAlive Crashed) and ReportCrash writes a report each time; the others do
    # nothing without a network and cost 58-75 s of guest CPU each in the first 38 min. Do not cut
    # geod (navd spins, 833 s), cloudd (transparencyd retries CloudKit), mobileassetd or CommCenter.
    'com.apple.DumpPanic',
    'com.apple.amsengagementd',
    'com.apple.mediaanalysisd',
    'com.apple.photoanalysisd',
    # M2 frame-chase extras (low risk; re-add dasd if SpringBoard needs it):
    'com.asoft.spindump',   # our diagnostic sampler (empty output, CPU sink)
    'com.apple.dasd',       # background activity scheduler
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
    removed_labels = sorted(j.get('Label') for j in jobs.values() if j.get('Label') in REMOVE)
    for k in [k for k, j in jobs.items() if j.get('Label') in REMOVE]:
        del jobs[k]
    with open(path, 'wb') as f:
        plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, st.st_uid, st.st_gid)
    os.chmod(path, st.st_mode & 0o7777)
    print('removed %d jobs: %s' % (len(removed_labels), removed_labels))
    print('not found (already gone / typo): %s' % sorted(REMOVE - set(removed_labels)))
    print('remaining LaunchDaemons: %d' % len(jobs))

if __name__ == '__main__':
    main()
