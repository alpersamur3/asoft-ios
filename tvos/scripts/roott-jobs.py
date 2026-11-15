"""launchd job fixes for the tvOS root, as rootw-jobs.py does for watchOS: backboardd loses its _Conclave
(conclave id + xpcproxy's POSIX_SPAWN_SETEXEC -> EINVAL); PineBoard (tvOS's SpringBoard) has no _Conclave or
hardware limit in 24K122 (checked by inspectt.sh). Works on launchd.plist as root26-tweaks.py left it. Idempotent.

    roott-jobs.py MOUNTED_ROOT
"""
import os
import plistlib
import sys

path = os.path.join(sys.argv[1], 'System/Library/xpc/launchd.plist')
st = os.stat(path)
with open(path, 'rb') as f:
    plist = plistlib.load(f)
jobs = {v.get('Label'): v for v in plist['LaunchDaemons'].values()}
for label in ('com.apple.PineBoard', 'com.apple.backboardd'):
    job = jobs[label]
    if job.pop('_Conclave', None):
        print(label, '_Conclave removed')
    lim = job.get('LimitLoadFromHardware')
    if lim and 'diagnostics' in lim.get('osenvironment', []):
        lim['osenvironment'].remove('diagnostics')
        if not lim['osenvironment']:
            del lim['osenvironment']
        if not lim:
            del job['LimitLoadFromHardware']
        print(label, 'diagnostics limit removed')
with open(path, 'wb') as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
os.chown(path, st.st_uid, st.st_gid)
os.chmod(path, st.st_mode & 0o7777)
