#!/usr/bin/env python3
"""SpringBoard bring-up prefs for the iOS 26 Data volume, the iOS 26 counterpart
of Yol A's tools/sweet-root-tweaks.py (iOS 16). Run via root26-do.sh on the
mounted root ($R = p1, with p2/Data on $R/private/var):

  root26-do.sh DISK.qcow2 'python3 SCRIPTS/root26-prefs.py $R'

Writes (Data volume, /private/var):
  migration        LastSystemVersion so DataMigration does not run for an hour
  springboard      BKNoWatchdogs, purplebuddy launch-watchdog exception, no
                   cloud-configuration UI
  purplebuddy      Setup skipped (SetupDone/SetupFinishedAllSteps), mini-buddy
                   flags off
  activation       mobileactivationd data ark seeded -ActivationState Activated
                   (if its system container exists yet)
  audio            VirtualAudio HAL plug-in disabled, MediaToolbox
                   StartRecorderServer off (mediaserverd crash loop w/o a GPU)
Build/version are read from the image's SystemVersion.plist. Idempotent.
launchd/containers are done separately by root26-tweaks.py at build time.
"""
import glob, os, plistlib, shutil, sys

MOBILE = 501


def load(path):
    with open(path, 'rb') as f:
        return plistlib.load(f)


def save(path, data, uid, gid, mode, fmt=plistlib.FMT_BINARY):
    with open(path, 'wb') as f:
        plistlib.dump(data, f, fmt=fmt)
    os.chown(path, uid, gid)
    os.chmod(path, mode)


def sysver(root):
    for p in ('System/Library/CoreServices/SystemVersion.plist',
              'System/Library/CoreServices/SystemVersion-iOS.plist'):
        fp = os.path.join(root, p)
        if os.path.exists(fp):
            d = load(fp)
            return d.get('ProductBuildVersion', '23G90'), d.get('ProductVersion', '26.6.2')
    return '23G90', '26.6.2'


def merge_pref(root, name, values):
    d = os.path.join(root, 'private/var/mobile/Library/Preferences')
    os.makedirs(d, exist_ok=True)
    try:
        os.chown(d, MOBILE, MOBILE)
    except OSError:
        pass
    path = os.path.join(d, name + '.plist')
    data = load(path) if os.path.exists(path) else {}
    data.update(values)
    save(path, data, MOBILE, MOBILE, 0o600)
    print('pref', name, sorted(values))


def find_container(root, kind, identifier):
    for meta in glob.glob(os.path.join(root, 'private/var/containers', kind, '*',
                                       '.com.apple.mobile_container_manager.metadata.plist')):
        try:
            if load(meta).get('MCMMetadataIdentifier') == identifier:
                return os.path.dirname(meta)
        except Exception:
            pass
    return None


def activation(root, build, version):
    c = find_container(root, 'Data/System', 'com.apple.mobileactivationd')
    if c is None:
        print('warning: no mobileactivationd system container yet; data ark skipped')
        return
    d = os.path.join(c, 'Library/internal')
    os.makedirs(d, exist_ok=True)
    os.chown(d, MOBILE, MOBILE)
    os.chmod(d, 0o755)
    save(os.path.join(d, 'data_ark.plist'), {
        '-ActivationState': 'Activated', '-BrickState': False,
        '-BuildVersion': build, '-ProductVersion': version,
        '-DataMigrationCompleted': True, '-PreSydroDataMigrationCompleted': True,
    }, MOBILE, MOBILE, 0o600)
    print('data ark', d)


def audio(root):
    src = os.path.join(root, 'Library/Audio/Plug-Ins/HAL/VirtualAudio.plugin')
    dst_dir = os.path.join(root, 'Library/Audio/Plug-Ins/HAL.disabled')
    if os.path.exists(src):
        os.makedirs(dst_dir, exist_ok=True)
        shutil.move(src, dst_dir)
        print('VirtualAudio.plugin disabled')
    for conf in glob.glob(os.path.join(root, 'System/Library/Frameworks/MediaToolbox.framework/*/SubServerConfiguration.plist')):
        st = os.stat(conf)
        data = load(conf)
        data['StartRecorderServer'] = False
        save(conf, data, st.st_uid, st.st_gid, st.st_mode & 0o7777, plistlib.FMT_XML)
        print('StartRecorderServer off', os.path.relpath(conf, root))


def main():
    if len(sys.argv) != 2 or not os.path.isdir(os.path.join(sys.argv[1], 'System/Library/xpc')):
        sys.exit(__doc__)
    root = sys.argv[1]
    build, version = sysver(root)
    print('build', build, 'version', version)
    activation(root, build, version)
    audio(root)
    merge_pref(root, 'com.apple.migration', {
        'LastSystemVersion': build,
        'DMUserDataDisposition': {'SyntheticDidUpgrade': False, 'buildVersion': build}})
    merge_pref(root, 'com.apple.springboard', {
        'BKNoWatchdogs': True,
        'FBLaunchWatchdogExceptions': {'com.apple.purplebuddy': 100.0},
        'MCForceShowCloudConfigurationUI': False})
    merge_pref(root, 'com.apple.purplebuddy', {
        'SetupDone': True, 'SetupFinishedAllSteps': True, 'SetupVersion': 11,
        'daemonizeNeedsToRun': False})
    merge_pref(root, 'com.apple.purplebuddy.notbackedup', {
        k: False for k in ('ShouldRunDiagnosticsMiniBuddy', 'ShouldRunHSA2MiniBuddy',
                           'ShouldRunKeychainSyncMiniBuddy', 'ShouldRunMesaMiniBuddy',
                           'ShouldRunPaymentMiniBuddy', 'ShouldRunStandardMiniBuddy',
                           'SilentICDPUpgrade')})
    merge_pref(root, 'com.apple.managedconfiguration.notbackedup', {
        'LockdownActivationIndicatesCloudConfigurationAvailable': False})


if __name__ == '__main__':
    main()
