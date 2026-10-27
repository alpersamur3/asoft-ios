#!/usr/bin/env python3
"""Remove the 'diagnostics' osenvironment exclusion from com.apple.SpringBoard's
launchd job so SpringBoard also loads under a diagnostics osenvironment (we boot
with boot-ios-diagnostics=1 so keybagd skips MKB_INIT; backboardd has no such
exclusion and runs, but SpringBoard's LimitLoadFromHardware held it back). Only
this one job, only the 'diagnostics' entry. Run via root26-do.sh:
  root26-sb-undiag.py MOUNTED_ROOT
"""
import os, plistlib, sys
root = sys.argv[1]
path = os.path.join(root, 'System/Library/xpc/launchd.plist')
st = os.stat(path)
d = plistlib.load(open(path, 'rb'))
k = '/System/Library/LaunchDaemons/com.apple.SpringBoard.plist'
j = d['LaunchDaemons'][k]
lh = j.get('LimitLoadFromHardware')
before = lh.get('osenvironment') if isinstance(lh, dict) else None
if isinstance(lh, dict) and isinstance(lh.get('osenvironment'), list):
    lh['osenvironment'] = [e for e in lh['osenvironment'] if e != 'diagnostics']
    if not lh['osenvironment']:
        del lh['osenvironment']
    if not lh:
        del j['LimitLoadFromHardware']
with open(path, 'wb') as f:
    plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
os.chown(path, st.st_uid, st.st_gid); os.chmod(path, st.st_mode & 0o7777)
after = j.get('LimitLoadFromHardware')
print('SpringBoard LimitLoadFromHardware: %r -> %r' % (before, after))
