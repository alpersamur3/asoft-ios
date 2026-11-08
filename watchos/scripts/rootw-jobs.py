"""launchd job fixes for the watchOS root, as root26-sb-undiag.py + root26-bbd-fix.py do for iOS:
com.apple.Carousel (watchOS's SpringBoard) also loads under the diagnostics osenvironment we boot
with, and Carousel and backboardd lose their _Conclave (conclave id + xpcproxy's POSIX_SPAWN_SETEXEC
-> EINVAL). Works on launchd.plist as root26-tweaks.py left it. Idempotent.

    rootw-jobs.py MOUNTED_ROOT
"""
import os, plistlib, sys

path = os.path.join(sys.argv[1], 'System/Library/xpc/launchd.plist')
st = os.stat(path)
with open(path, 'rb') as f:
    plist = plistlib.load(f)
jobs = {v.get('Label'): v for v in plist['LaunchDaemons'].values()}
for label in ('com.apple.Carousel', 'com.apple.backboardd'):
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
