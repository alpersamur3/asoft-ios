"""VirtualAudio.plugin in or out of the HAL plug-in folder of a mounted visionOS root.
  on   /Library/Audio/Plug-Ins/HAL.disabled/VirtualAudio.plugin -> HAL: the sound disk. With virtio-snd and
       VPhoneVirtIOSound.driver, audiomxd's VirtualAudio endpoint manager needs it (without it:
       "vaemGetVirtualAudioPlugin ERROR getting AudioObjectID for the VirtualAudio plug-in")
  off  HAL/VirtualAudio.plugin -> HAL.disabled: the silent disk (audiomxd takes about one vCPU with it), and
       what ios26's root26-prefs.py leaves (its audio() disables it on every run)
Idempotent: a plug-in already where it should be is left; one in neither folder is an error.
    rootx-va.py MOUNTED_ROOT on|off
"""
import os, shutil, sys

if len(sys.argv) != 3 or sys.argv[2] not in ('on', 'off'):
    sys.exit(__doc__)
root, mode = sys.argv[1], sys.argv[2]
base = os.path.join(root, 'Library/Audio/Plug-Ins')
hal, dis = os.path.join(base, 'HAL'), os.path.join(base, 'HAL.disabled')
src, dst = (dis, hal) if mode == 'on' else (hal, dis)
if os.path.isdir(os.path.join(dst, 'VirtualAudio.plugin')):
    print(f'VirtualAudio.plugin is in {os.path.relpath(dst, root)} already')
    sys.exit(0)
if not os.path.isdir(os.path.join(src, 'VirtualAudio.plugin')):
    sys.exit(f'no VirtualAudio.plugin in {os.path.relpath(hal, root)} or {os.path.relpath(dis, root)}')
if not os.path.isdir(dst):
    os.mkdir(dst)
    os.chown(dst, 0, 0)
    os.chmod(dst, 0o755)
shutil.move(os.path.join(src, 'VirtualAudio.plugin'), dst)
if mode == 'on' and not os.listdir(dis):
    os.rmdir(dis)
print(f'VirtualAudio.plugin -> {os.path.relpath(dst, root)}')
