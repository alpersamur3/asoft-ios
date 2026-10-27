#!/usr/bin/env python3
"""First-boot changes to the iOS 26 root made by mk-root26.sh (M2), after Yol A's
tools/sweet-root-tweaks.py (iOS 16). Run as root on the mounted HFS+ root:

  root26-tweaks.py MOUNTED_ROOT

launchd.plist (/System/Library/xpc, launchd's job cache; the original is kept
as launchd.plist.orig):
  - com.asoft.bash: bash -i on /dev/console (the serial console), as in M1
  - _PanicOnCrash -> _PanicOnCrasX: a crashing daemon must not panic the system
  - CommCenter jobs removed (no baseband)
containers: /private/var/containers/{Bundle,Data/System,Shared/SystemGroup,Temp}
Idempotent.
"""
import os, plistlib, shutil, sys

BASH_JOB = {
    'Label': 'com.asoft.bash',
    'ProgramArguments': ['/bin/bash', '-i'],
    'StandardInPath': '/dev/console',
    'StandardOutPath': '/dev/console',
    'StandardErrorPath': '/dev/console',
    'ProcessType': 'Interactive',
    'KeepAlive': True,
    'RunAtLoad': True,
    'UserName': 'root',
    'POSIXSpawnType': 'Interactive',
}


def launchd(root):
    path = os.path.join(root, 'System/Library/xpc/launchd.plist')
    orig = path + '.orig'
    if not os.path.exists(orig):
        shutil.copy2(path, orig)
    st = os.stat(orig)
    with open(orig, 'rb') as f:
        plist = plistlib.load(f)
    print('launchd.plist keys:', sorted(plist))
    jobs = plist['LaunchDaemons']
    renamed = 0
    for job in jobs.values():
        if '_PanicOnCrash' in job:
            job['_PanicOnCrasX'] = job.pop('_PanicOnCrash')
            renamed += 1
    removed = [k for k, j in jobs.items() if j.get('Label') in ('com.apple.CommCenter',)]
    for k in removed:
        del jobs[k]
    jobs['/System/Library/LaunchDaemons/com.asoft.bash.plist'] = BASH_JOB
    with open(path, 'wb') as f:
        plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY)
    os.chown(path, st.st_uid, st.st_gid)
    os.chmod(path, st.st_mode & 0o7777)
    print(f'launchd.plist: {len(jobs)} daemons, {renamed} _PanicOnCrash renamed, '
          f'{len(removed)} CommCenter removed, com.asoft.bash added')


def containers(root):
    base = os.path.join(root, 'private/var/containers')
    for sub, uid in (('Bundle', 33), ('Data/System', 0), ('Shared/SystemGroup', 0), ('Temp', 0)):
        d = os.path.join(base, sub)
        if not os.path.isdir(d):
            os.makedirs(d)
            os.chown(d, uid, uid)
            os.chmod(d, 0o755)
            print('mkdir', d)


def main():
    if len(sys.argv) != 2 or not os.path.isdir(os.path.join(sys.argv[1], 'System/Library/xpc')):
        sys.exit(__doc__)
    launchd(sys.argv[1])
    containers(sys.argv[1])


if __name__ == '__main__':
    main()
