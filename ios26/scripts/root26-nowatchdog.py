#!/usr/bin/env python3
"""Turn FrontBoard's scene watchdogs off for every process on an iOS 26 root.

  root26-nowatchdog.py MOUNTED_ROOT

Under TCG a poster extension's first scene takes longer than FrontBoard's
10 s scene-create allowance (its Metal shaders compile on first use), so
PosterBoard's FrontBoard kills it (0x8BADF00D) before the wallpaper is drawn.
FrontBoard reads BKNoWatchdogs and FBDisableWatchdog from user defaults;
com.apple.springboard already has BKNoWatchdogs (root26-prefs.py), PosterBoard
reads its own domain and the global one. Writes both keys to mobile's
.GlobalPreferences and PosterBoard's container preferences. Idempotent.
"""
import glob, os, plistlib, sys

KEYS = {'BKNoWatchdogs': True, 'FBDisableWatchdog': True}


def update(path, owner=(501, 501)):
    d = {}
    if os.path.exists(path):
        with open(path, 'rb') as f:
            d = plistlib.load(f)
    d.update(KEYS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, *owner)
    os.chmod(path, 0o600)
    print('wrote', path.split('/private/var/', 1)[-1])


def main():
    root = sys.argv[1]
    update(os.path.join(root, 'private/var/mobile/Library/Preferences/.GlobalPreferences.plist'))
    for meta in glob.glob(os.path.join(root, 'private/var/mobile/Containers/Data/Application/*/.com.apple.mobile_container_manager.metadata.plist')):
        with open(meta, 'rb') as f:
            if plistlib.load(f).get('MCMMetadataIdentifier') == 'com.apple.PosterBoard':
                update(os.path.join(os.path.dirname(meta), 'Library/Preferences/com.apple.PosterBoard.plist'))


if __name__ == '__main__':
    main()
