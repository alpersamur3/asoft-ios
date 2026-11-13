"""Preferences for the tvOS root, mobile's (UID 501) files under private/var (Data volume mounted):
 - com.apple.purplebuddy: setup finished as tvOS's own Setup records it (vphone-cli tvos_support.md, after a
   native setup: SetupDone=true, TVBuddyCompletedSuccessfully=true, TVSetupVersion=15)
 - FrontBoard/backboard watchdogs off (first launches under TCG take > 10 s), as rootw-screen.py / rootx-prefs.py
Idempotent.
    roott-prefs.py MOUNTED_ROOT
"""
import os
import plistlib
import sys

MOBILE = 501
P = os.path.join(sys.argv[1], 'private/var/mobile/Library/Preferences')
os.makedirs(P, exist_ok=True)


def upd(name, vals):
    path = os.path.join(P, name + '.plist')
    d = {}
    if os.path.exists(path):
        with open(path, 'rb') as f:
            d = plistlib.load(f)
    d.update(vals)
    with open(path, 'wb') as f:
        plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, MOBILE, MOBILE)
    os.chmod(path, 0o600)
    print(name, sorted(vals))


upd('com.apple.purplebuddy', {'SetupDone': True, 'TVBuddyCompletedSuccessfully': True, 'TVSetupVersion': 15,
                              'SetupFinishedAllSteps': True})
# screen saver / idle screen off: after 5 idle minutes PineBoard put IdleScreen up (boot 1, 05:03:52), which is
# black without downloaded aerials (keys from TVIdleServices/PineBoard in the 24K122 shared cache)
upd('com.apple.TVScreenSaver', {'IsScreenSaverEnabled': False, 'IsIdleScreenEnabled': False,
                                'ScreenSaverIdleDelay': 0})
upd('.GlobalPreferences', {'BKNoWatchdogs': True, 'FBDisableWatchdog': True})
upd('com.apple.PineBoard', {'BKNoWatchdogs': True, 'FBDisableWatchdog': True})
upd('com.apple.backboardd', {'BKNoWatchdogs': True})
