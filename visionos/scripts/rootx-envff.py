"""Turn on FeatureFlag RealityEnvironment/ShowEnvironmentsOnSimulator (read 2026-11-08: RealityEnvironment's
SystemEnvironmentSceneAsset.state @0x1000586d8 returns SFBSEnvironmentState 3 = Unavailable for every non-synthetic
environment when SFBSIsRunningOnPhysicalHardware() is false (kern.hv_vmm_present != 0) and this flag is off; the
defaults key written by rootx-env.py is never read). Writes the flag in two places FeatureFlags reads:
  1. /System/Library/FeatureFlags/Domain/RealityEnvironment.plist (stock: BackgroundWhenIdle only; kept)
  2. /private/var/preferences/FeatureFlags/Domain/RealityEnvironment.plist (= /Library/Preferences/FeatureFlags)
    rootx-envff.py MOUNTED_ROOT
"""
import os, plistlib, sys
root = sys.argv[1]
flag = {'ShowEnvironmentsOnSimulator': {'Enabled': True}}
sysp = os.path.join(root, 'System/Library/FeatureFlags/Domain/RealityEnvironment.plist')
st = os.stat(sysp)
d = plistlib.loads(open(sysp, 'rb').read())
d.update(flag)
with open(sysp, 'wb') as f:
    plistlib.dump(d, f, fmt=plistlib.FMT_XML)
os.chown(sysp, st.st_uid, st.st_gid); os.chmod(sysp, st.st_mode & 0o7777)
print('system', sysp, '->', d)
var = os.path.join(root, 'private/var/preferences/FeatureFlags/Domain')
for p in (os.path.dirname(var), var):
    if not os.path.isdir(p):
        os.mkdir(p); os.chown(p, 0, 0); os.chmod(p, 0o755)
datap = os.path.join(var, 'RealityEnvironment.plist')
d2 = {'BackgroundWhenIdle': {'Enabled': True}}
d2.update(flag)
with open(datap, 'wb') as f:
    plistlib.dump(d2, f, fmt=plistlib.FMT_XML)
os.chown(datap, 0, 0); os.chmod(datap, 0o644)
print('data', datap, '->', d2)
