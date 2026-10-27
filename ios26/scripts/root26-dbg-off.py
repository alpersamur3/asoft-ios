#!/usr/bin/env python3
"""Strip leftover debug EnvironmentVariables from the SpringBoard and backboardd
launchd jobs (DYLD_PRINT_*, OS_ACTIVITY_DT_MODE, CA_* ) that a prior debugging
session left in. Under TCG the DYLD_PRINT_* logging is so heavy that SpringBoard
never finishes dynamic linking before being killed (18 respawns, 22k dyld lines
each, never reaching its own code). Keeps StandardErrorPath so a real crash still
lands in sb.log/bbd.log. Run as root on the mounted root:

  root26-dbg-off.py MOUNTED_ROOT
"""
import os, plistlib, sys

DROP = {'OS_ACTIVITY_DT_MODE', 'CA_ASSERT_MAIN_THREAD_TRANSACTIONS',
        'CA_DEBUG_TRANSACTIONS'}
DROP_PREFIX = ('DYLD_PRINT_',)

root = sys.argv[1]
path = os.path.join(root, 'System/Library/xpc/launchd.plist')
st = os.stat(path)
d = plistlib.load(open(path, 'rb'))
for key in ('/System/Library/LaunchDaemons/com.apple.SpringBoard.plist',
            '/System/Library/LaunchDaemons/com.apple.backboardd.plist'):
    j = d['LaunchDaemons'].get(key)
    if not j:
        continue
    env = j.get('EnvironmentVariables') or {}
    kept = {k: v for k, v in env.items()
            if k not in DROP and not k.startswith(DROP_PREFIX)}
    if kept:
        j['EnvironmentVariables'] = kept
    else:
        j.pop('EnvironmentVariables', None)
    print('%s env now: %s' % (key.split('/')[-1], kept))
with open(path, 'wb') as f:
    plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
os.chown(path, st.st_uid, st.st_gid)
os.chmod(path, st.st_mode & 0o7777)
print('debug env stripped')
