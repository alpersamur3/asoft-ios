"""launchd job fixes for the visionOS root, as rootw-jobs.py does for watchOS: com.apple.SurfBoard (visionOS's
SpringBoard) also loads under the diagnostics osenvironment we boot with, and SurfBoard and backboardd lose
their _Conclave (conclave id + xpcproxy's POSIX_SPAWN_SETEXEC -> EINVAL). _PanicOnCrash is already renamed by
root26-tweaks.py (polarisd, realitycamerad, realitycoprocessorloaderd, arkitd among them). Idempotent.

    rootx-jobs.py MOUNTED_ROOT
"""
import os, plistlib, sys

path = os.path.join(sys.argv[1], 'System/Library/xpc/launchd.plist')
st = os.stat(path)
with open(path, 'rb') as f:
    plist = plistlib.load(f)
jobs = {v.get('Label'): v for v in plist['LaunchDaemons'].values()}
for label in ('com.apple.SurfBoard', 'com.apple.backboardd'):
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
left = [k for k, v in jobs.items() if '_PanicOnCrash' in v]
print('jobs still with _PanicOnCrash:', left)
with open(path, 'wb') as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
os.chown(path, st.st_uid, st.st_gid)
os.chmod(path, st.st_mode & 0o7777)
