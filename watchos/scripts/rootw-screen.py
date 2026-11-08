"""Keep the watch display on. -[CSLBacklightIdleProviderAssessor init] (Carousel framework, watchOS 27.2)
reads AutoScreenOffSeconds and DisableAutoDim from NSUserDefaults suite "com.apple.system.prefs"
(DisableAutoDim -> "autoOffDisabled is YES, screen will not idle off": a BLSPreventBacklightIdle
assertion); _isTetheredDemoMode reads EnableNanoTetheredDemoMode from suite "com.apple.demo-settings".
Written to mobile's preference files. Idempotent.
    rootw-screen.py MOUNTED_ROOT
"""
import os, plistlib, sys

P = os.path.join(sys.argv[1], 'private/var/mobile/Library/Preferences')
for name, add in (('com.apple.system.prefs', {'AutoScreenOffSeconds': 86400, 'DisableAutoDim': True}),
                  ('com.apple.demo-settings', {'EnableNanoTetheredDemoMode': True}),
                  # FrontBoard's scene watchdogs (Carousel hosts the apps; first launches under TCG take > 10 s)
                  ('.GlobalPreferences', {'BKNoWatchdogs': True, 'FBDisableWatchdog': True}),
                  ('com.apple.Carousel', {'DisableAutoDim': True, 'AutoScreenOffSeconds': 86400,
                                          'BKNoWatchdogs': True, 'FBDisableWatchdog': True})):
    path = os.path.join(P, name + '.plist')
    d = {}
    if os.path.exists(path):
        with open(path, 'rb') as f:
            d = plistlib.load(f)
    d.update(add)
    with open(path, 'wb') as f:
        plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, 501, 501); os.chmod(path, 0o600)
    print(name, sorted(add))
