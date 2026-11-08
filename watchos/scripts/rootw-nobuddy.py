"""Skip watchOS Setup (the iPhone pairing flow) on a watchOS root: mobile's com.apple.nanobuddy gets
NanoSetupSupport's own override and completion keys. _PSNanoIsBricked and _PBNanoRegistryWantsBuddy
read ForceNoBuddy first ("PSSetupAssistantNeedsToRun is NO due to ForceNoBuddy."),
_PBNanoSetupAssistantHasCompleted compares SetupVersion; backboardd's accessibility code reads SetupDone.
Run on the mounted root with the Data volume on private/var. Idempotent.

    rootw-nobuddy.py MOUNTED_ROOT
"""
import os, plistlib, sys

path = os.path.join(sys.argv[1], 'private/var/mobile/Library/Preferences/com.apple.nanobuddy.plist')
d = {}
if os.path.exists(path):
    with open(path, 'rb') as f:
        d = plistlib.load(f)
d.update({'ForceNoBuddy': True, 'SetupDone': True, 'SetupVersion': 100})
with open(path, 'wb') as f:
    plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
os.chown(path, 501, 501)
os.chmod(path, 0o600)
print(path, d)
