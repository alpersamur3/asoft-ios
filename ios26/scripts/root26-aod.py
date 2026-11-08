#!/usr/bin/env python3
"""Always On Display's and Auto-Lock Never's part of the iOS 26 root, run via root26-do.sh on the
mounted root ($R = p1, with p2/Data on $R/private/var), after root26-prefs.py:

  root26-do.sh DISK.qcow2 'python3 -I SCRIPTS/root26-aod.py $R'

Writes (Data volume, /private/var):
  display      Auto-Lock Never (maxInactivity 2147483647, as Settings writes Never) and a Lock
               Screen that does not go dark on its own (SBMinimumLockscreenIdleTime): iOS sleeps
               only at the side button, which takes it to its Always On Display. The emulator's
               window covers a display that is off, so nothing is lost by never dimming.
  gestalt      MobileGestalt's cache moved aside (root26-mgcache.py reset): it is rebuilt only
               when the OS build changes, and the answers this needs (DeviceSupportsAlwaysOnTime
               from the device tree's /arm-io/disp0, dt-aod.py, and the flipbook one, patched in
               libMobileGestalt by the apps step) must be computed again on the next boot.

The libMobileGestalt patch itself (dyld_shared_cache_arm64e.15: 0x1b22c75fc mov w0,#1 -> #0, the
AlwaysOnDisplayFlipbook answer; backboardd asserts on the paravirtual display's missing hardware
flipbook otherwise) goes in with the apps step's other cache patches (apply-apps.sh). Idempotent.
"""
import importlib.util, os, sys

NEVER = 2147483647


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'),
                                                  os.path.join(os.path.dirname(os.path.abspath(__file__)), name + '.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main():
    if len(sys.argv) != 2 or not os.path.isdir(os.path.join(sys.argv[1], 'System/Library/xpc')):
        sys.exit(__doc__)
    root = sys.argv[1]
    prefs = module('root26-prefs')
    prefs.auto_lock(root, NEVER)
    prefs.merge_pref(root, 'com.apple.springboard', {'SBMinimumLockscreenIdleTime': NEVER})
    print('lock screen idle time', NEVER, 's')
    cache = os.path.join(root, module('root26-mgcache').CACHE)
    if os.path.exists(cache):
        os.replace(cache, cache + '.stale')
        print('MobileGestalt cache moved to .stale')
    else:
        print('no MobileGestalt cache (it is made on the next boot)')


if __name__ == '__main__':
    main()
