#!/usr/bin/env python3
"""M2: drop a stale MobileGestalt cache so MobileGestalt recomputes its answers
from the current device tree on the next boot.

The cache (systemgroup.com.apple.mobilegestaltcache/.../com.apple.MobileGestalt.plist)
is only rebuilt when the OS build changes. Ours was written before
/chosen/display-scale became 3, so main-screen-scale stays 0 and SpringBoard
traps in FBSDisplayMode ("infxinf@0x (1179x2556/0)"). Run as root on the
mounted root with the Data volume on private/var:

  root26-mgcache.py MOUNTED_ROOT reset|restore

Reversible: reset renames the cache to .stale, restore puts it back.
"""
import os, sys

CACHE = ('private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/'
         'Library/Caches/com.apple.MobileGestalt.plist')


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    root, mode = sys.argv[1], sys.argv[2]
    path = os.path.join(root, CACHE)
    stale = path + '.stale'
    if mode == 'reset':
        if os.path.exists(path):
            os.replace(path, stale)
            print('moved MobileGestalt cache to .stale')
        else:
            print('no MobileGestalt cache (already reset)')
    elif mode == 'restore':
        if not os.path.exists(stale):
            sys.exit('no .stale cache to restore')
        os.replace(stale, path)
        print('restored MobileGestalt cache from .stale')
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
