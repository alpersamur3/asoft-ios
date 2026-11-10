"""RealityKeyboard's slide-to-type introduction off: UIKit presents it at the keyboard's first start, its video resource comes
back nil and -[NSArray arrayWithObjects:count:] throws (updateVideoLayerWithNewVideo:), every 13 s for ever. The TextInput keys
DidShowContinuousPathIntroduction and KeyboardContinuousPathEnabled, in mobile's keyboard and global domains.
    rootx-keys.py MOUNTED_ROOT
"""
import os, plistlib, sys
P = os.path.join(sys.argv[1], 'private/var/mobile/Library/Preferences')
add = {'DidShowContinuousPathIntroduction': True, 'KeyboardContinuousPathEnabled': False}
for name in ('com.apple.keyboard.preferences', 'com.apple.Preferences', '.GlobalPreferences'):
    path = os.path.join(P, name + '.plist')
    d = {}
    if os.path.exists(path):
        with open(path, 'rb') as f:
            d = plistlib.load(f)
    d.update(add)
    with open(path, 'wb') as f:
        plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, 501, 501); os.chmod(path, 0o600)
    print(name, len(d))
