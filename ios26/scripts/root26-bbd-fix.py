#!/usr/bin/env python3
"""Restore backboardd's job to original ProgramArguments (undo the sh/stderr/
DT_MODE diagnostic wrap) and remove its _Conclave so xpcproxy's POSIX_SPAWN_
SETEXEC isn't rejected (conclave id + SETEXEC -> EINVAL -> backboardd dies).
The sh-wrapper test proved backboardd runs fine without the conclave attribute.
  root26-bbd-fix.py MOUNTED_ROOT
"""
import os, plistlib, sys
root = sys.argv[1]
path = os.path.join(root, 'System/Library/xpc/launchd.plist')
st = os.stat(path)
d = plistlib.load(open(path, 'rb'))
j = d['LaunchDaemons']['/System/Library/LaunchDaemons/com.apple.backboardd.plist']
if '_OrigProg' in j:
    j['ProgramArguments'] = j.pop('_OrigProg')
else:
    j['ProgramArguments'] = ['/usr/libexec/backboardd']
for k in ('StandardErrorPath', 'StandardOutPath'):
    j.pop(k, None)
env = j.get('EnvironmentVariables') or {}
for e in ('OS_ACTIVITY_DT_MODE', 'CA_DEBUG_TRANSACTIONS'):
    env.pop(e, None)
if env: j['EnvironmentVariables'] = env
else: j.pop('EnvironmentVariables', None)
before = j.get('_Conclave')
j.pop('_Conclave', None)
with open(path, 'wb') as f:
    plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
os.chown(path, st.st_uid, st.st_gid); os.chmod(path, st.st_mode & 0o7777)
print('backboardd restored; _Conclave %r -> removed; prog=%s' % (before, j['ProgramArguments']))
