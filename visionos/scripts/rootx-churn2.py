"""Second churn cut (after rootx-churn.py), measured on boot 62 with audio on (VISIONOS.md §12.3, gtopx.py, 65 s idle):
audioanalyticsd 30.0 CPU-s (0.46 vCPU), rtcreportingd 8.9 (0.14); analyticsagent, inputanalyticsd and wifianalyticsd are
the same kind (telemetry only). Removed from the current launchd.plist; backup launchd.plist.prechurn2.
    rootx-churn2.py MOUNTED_ROOT
"""
import os, plistlib, shutil, sys

REMOVE = {'com.apple.audioanalyticsd', 'com.apple.rtcreportingd', 'com.apple.analyticsagent',
          'com.apple.inputanalyticsd', 'com.apple.wifianalyticsd'}
root = sys.argv[1]
path = os.path.join(root, 'System/Library/xpc/launchd.plist')
st = os.stat(path)
if not os.path.exists(path + '.prechurn2'):
    shutil.copy2(path, path + '.prechurn2')
with open(path, 'rb') as f:
    plist = plistlib.load(f)
jobs = plist['LaunchDaemons']
gone = sorted(j['Label'] for j in jobs.values() if j.get('Label') in REMOVE)
for k in [k for k, j in jobs.items() if j.get('Label') in REMOVE]:
    del jobs[k]
with open(path, 'wb') as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
os.chown(path, st.st_uid, st.st_gid)
os.chmod(path, st.st_mode & 0o7777)
print('removed', gone, 'not found', sorted(REMOVE - set(gone)), 'remaining', len(jobs))
