"""The Accessibility Shortcut off (TripleClickChoice = []: three Digital Crown presses do nothing; it was [5],
VoiceOver) and VoiceOver off, in mobile's com.apple.Accessibility of a mounted root. Prints before and after.
A root without the file yet (no boot has written it, and root26-prefs.py did not run) gets one with these keys.
    a11y-off.py MOUNTED_ROOT
"""
import os, plistlib, sys

MOBILE = 501
d = os.path.join(sys.argv[1], 'private/var/mobile/Library/Preferences')
p = os.path.join(d, 'com.apple.Accessibility.plist')
keys = ('TripleClickChoice', 'VoiceOverTouchEnabled', 'VOTIsRunningKey')
v, fmt = {}, plistlib.FMT_BINARY
if os.path.exists(p):
    raw = open(p, 'rb').read()
    fmt = plistlib.FMT_BINARY if raw.startswith(b'bplist') else plistlib.FMT_XML
    v = plistlib.loads(raw)
    print('before', {k: v.get(k) for k in keys})
else:
    print('before: no', p[len(sys.argv[1]):], '(made now)')
    os.makedirs(d, exist_ok=True)
v['TripleClickChoice'] = []
v['VoiceOverTouchEnabled'] = 0
v['VOTIsRunningKey'] = False
with open(p, 'wb') as f:
    plistlib.dump(v, f, fmt=fmt)
os.chown(p, MOBILE, MOBILE)
os.chmod(p, 0o600)
print('after ', {k: v.get(k) for k in keys})
