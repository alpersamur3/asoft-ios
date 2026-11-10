"""Third churn cut (after rootx-churn2.py): cloudtelemetryd, 6.1 CPU-s of 77 right after the Home view (boot 64,
VISIONOS.md §12.3), telemetry only. Removed from the current launchd.plist (any job table that holds it); backup
launchd.plist.prechurn3.
    rootx-churn3.py MOUNTED_ROOT
"""
import os, plistlib, shutil, sys

MATCH = ('cloudtelemetry',)
root = sys.argv[1]
path = os.path.join(root, 'System/Library/xpc/launchd.plist')
st = os.stat(path)
if not os.path.exists(path + '.prechurn3'):
    shutil.copy2(path, path + '.prechurn3')
with open(path, 'rb') as f:
    plist = plistlib.load(f)
gone = []
for table, jobs in plist.items():
    if not isinstance(jobs, dict):
        continue
    for k in [k for k, j in jobs.items() if isinstance(j, dict) and any(m in str(j.get('Label', '')).lower() for m in MATCH)]:
        gone.append((table, jobs[k].get('Label')))
        del jobs[k]
with open(path, 'wb') as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
os.chown(path, st.st_uid, st.st_gid)
os.chmod(path, st.st_mode & 0o7777)
print('removed', gone, 'tables', [t for t, j in plist.items() if isinstance(j, dict)])
