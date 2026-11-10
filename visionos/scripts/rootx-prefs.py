"""Preferences for the visionOS root, mobile's (UID 501) files under private/var (Data volume mounted):
 - com.apple.purplebuddy ForceNoBuddy: skip onboarding (vphone-cli PR #847; MuseBuddy SetupDone and
   BuddyRunVersion did not work there)
 - com.apple.userexperiencemanagerd PluginDenyList += RealityCameraUXMPlugin.plugin: without the IR cameras
   UXM cannot create that plugin's expert and stops (PR #847, manual step there)
 - FrontBoard/backboard watchdogs off (first launches under TCG take > 10 s), as rootw-screen.py
Idempotent.
    rootx-prefs.py MOUNTED_ROOT
"""
import os, plistlib, sys

P = os.path.join(sys.argv[1], 'private/var/mobile/Library/Preferences')
os.makedirs(P, exist_ok=True)


def upd(name, fn):
    path = os.path.join(P, name + '.plist')
    d = {}
    if os.path.exists(path):
        with open(path, 'rb') as f:
            d = plistlib.load(f)
    before = dict(d)
    fn(d)
    with open(path, 'wb') as f:
        plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, 501, 501)
    os.chmod(path, 0o600)
    # what this set (a domain such as .GlobalPreferences may hold kilobytes of other keys)
    print(name, {k: v for k, v in d.items() if before.get(k) != v or k not in before})


upd('com.apple.purplebuddy', lambda d: d.update({'ForceNoBuddy': True}))


def deny(d):
    lst = list(d.get('PluginDenyList', []))
    if 'RealityCameraUXMPlugin.plugin' not in lst:
        lst.append('RealityCameraUXMPlugin.plugin')
    d['PluginDenyList'] = lst


upd('com.apple.userexperiencemanagerd', deny)
upd('.GlobalPreferences', lambda d: d.update({'BKNoWatchdogs': True, 'FBDisableWatchdog': True}))
