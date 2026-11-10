"""First-use gates of the environment cards in RealityLauncher (read from its binary, 2026-11-08):
EnvironmentCellButton's action selects directly only if the AppStorage Bool UserHasLaunchedAnEnvironmentBefore
(standard defaults = com.apple.RealityLauncher) or RealityDialHasBeenRotated (suite com.apple.SurfBoard) is true;
otherwise it shows the "Adjust Immersion" alert (FIRST_LAUNCH_ALERT) whose OK continues. EnvironmentsWhatsNewViewModifier
shows the "Environments / Continue" sheet until HasSeenEnvironmentsWhatsNew (suite com.apple.SurfBoard) is true.
Set all three for user mobile.
    rootx-envfirst.py MOUNTED_ROOT
"""
import os, plistlib, sys
root = sys.argv[1]
prefs = os.path.join(root, 'private/var/mobile/Library/Preferences')
keys = {'com.apple.RealityLauncher.plist': {'UserHasLaunchedAnEnvironmentBefore': True},
        'com.apple.SurfBoard.plist': {'RealityDialHasBeenRotated': True, 'HasSeenEnvironmentsWhatsNew': True}}
for name, kv in keys.items():
    path = os.path.join(prefs, name)
    d, fmt, st = {}, plistlib.FMT_BINARY, None
    if os.path.exists(path):
        raw = open(path, 'rb').read()
        fmt = plistlib.FMT_BINARY if raw.startswith(b'bplist') else plistlib.FMT_XML
        d = plistlib.loads(raw)
        st = os.stat(path)
    d.update(kv)
    with open(path, 'wb') as f:
        plistlib.dump(d, f, fmt=fmt)
    if st:
        os.chown(path, st.st_uid, st.st_gid); os.chmod(path, st.st_mode & 0o7777)
    else:
        os.chown(path, 501, 501); os.chmod(path, 0o600)
    print(name, sorted(kv), 'new' if st is None else 'updated', '->', sorted(d))
