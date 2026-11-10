"""Diagnostic (2026-11-08): turn OFF FeatureFlag RealityLauncher/StereoEnvironmentIcons so the Home view's
environment cards use flat icons. On rootxi a card touch expands the icon into a stereo material that backboardd
rejects ("Custom Shader Credentials Check: FAIL"), the launcher blocks 3.7 s on the AssetLoadRequest and the card's
action never runs; this tells whether that is what swallows the tap. Not the fix: the trust check is.
Writes the flag in the system Domain plist and in the /private/var/preferences/FeatureFlags override.
    rootx-rlstereo.py MOUNTED_ROOT
"""
import os, plistlib, sys
root = sys.argv[1]
sysp = os.path.join(root, 'System/Library/FeatureFlags/Domain/RealityLauncher.plist')
st = os.stat(sysp)
d = plistlib.loads(open(sysp, 'rb').read())
d['StereoEnvironmentIcons'] = {'Enabled': False}
with open(sysp, 'wb') as f:
    plistlib.dump(d, f, fmt=plistlib.FMT_XML)
os.chown(sysp, st.st_uid, st.st_gid); os.chmod(sysp, st.st_mode & 0o7777)
print('system', sysp, '->', d)
var = os.path.join(root, 'private/var/preferences/FeatureFlags/Domain')
for p in (os.path.dirname(var), var):
    if not os.path.isdir(p):
        os.mkdir(p); os.chown(p, 0, 0); os.chmod(p, 0o755)
datap = os.path.join(var, 'RealityLauncher.plist')
with open(datap, 'wb') as f:
    plistlib.dump(d, f, fmt=plistlib.FMT_XML)
os.chown(datap, 0, 0); os.chmod(datap, 0o644)
print('data', datap, '->', d)
