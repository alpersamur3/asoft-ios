"""VirtualAudio's ProductID for the visionOS guest: 8010 (vphone-cli's choice for iPhone/iPad guests, whose routing
builds the speaker sub-ports). Without one, VirtualAudio reads ProductID 0 ("ProductID to int is: 0"), routes through
RoutingSettings_N71 with no speaker route and runs its aggregate device on Null_Device, so the virtio-snd speaker
(PuffinOutput) never starts (QEMU trace: no PCM_SET_PARAMS/START). Writes, in mobile's and root's domains:
  com.apple.coreaudio            VPhoneVirtIOSoundProductID = 8010 (the plugin sets ProductIDOverride in-process,
                                 names its speaker PuffinOutput and its microphone "Digital Mic"); the
                                 VPhoneVirtIOSoundDeviceUID override of rootx-audioprefs.py is dropped
  com.apple.audio.virtualaudio   ProductIDOverride = 8010 (on disk, as vphoned stores it: audiomxd's sandbox keeps the
                                 plugin's own write in memory)
    rootx-audioprod.py MOUNTED_ROOT [PRODUCT]
"""
import os, plistlib, sys
R = sys.argv[1]
product = int(sys.argv[2]) if len(sys.argv) > 2 else 8010
for home, uid in (('private/var/mobile', 501), ('private/var/root', 0)):
    d = os.path.join(R, home, 'Library/Preferences')
    for name, set_, drop in (('com.apple.coreaudio.plist', {'VPhoneVirtIOSoundProductID': product}, ['VPhoneVirtIOSoundDeviceUID']),
                             ('com.apple.audio.virtualaudio.plist', {'ProductIDOverride': product}, [])):
        path = os.path.join(d, name)
        v = {}
        if os.path.exists(path):
            with open(path, 'rb') as f:
                v = plistlib.load(f)
        for k in drop:
            v.pop(k, None)
        v.update(set_)
        with open(path, 'wb') as f:
            plistlib.dump(v, f, fmt=plistlib.FMT_BINARY)
        os.chown(path, uid, uid)
        os.chmod(path, 0o600)
        print(path.replace(R, ''), v)
