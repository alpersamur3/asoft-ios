#!/usr/bin/env python3
"""The three disk images an iOS root is built from, inside an IPSW (a zip file or a
whole block device holding one).

  ipsw-members.py IPSW                 list: ROLE OFFSET SIZE STORED NAME per image
  ipsw-members.py IPSW ROLE DEST       write that image's bytes to DEST (a file or a
                                       block device), inflating it if the zip deflated it

ROLE is OS, SystemOS or AppOS, from the BuildManifest's Erase identity of the D22 (iPhone
X). OFFSET is where an image's bytes start in IPSW when STORED is 1 (not deflated): a
loop device over that range reads it in place.
"""
import plistlib, shutil, struct, sys, zipfile

ROLES = {'OS': 'OS', 'SystemOS': 'Cryptex1,SystemOS', 'AppOS': 'Cryptex1,AppOS'}


def members(z):
    manifest = plistlib.loads(z.read('BuildManifest.plist'))
    for identity in manifest['BuildIdentities']:
        info = identity['Info']
        if info.get('DeviceClass', '').startswith('d22') and info.get('RestoreBehavior') == 'Erase':
            return {role: identity['Manifest'][key]['Info']['Path'] for role, key in ROLES.items()}
    sys.exit('no iPhone X (D22) erase identity in the BuildManifest')


def data_offset(f, info):
    """Where the member's data starts: after its local header and that header's own name and extra."""
    f.seek(info.header_offset)
    header = f.read(30)
    if header[:4] != b'PK\x03\x04':
        sys.exit('%s: bad local header' % info.filename)
    name_len, extra_len = struct.unpack('<HH', header[26:30])
    return info.header_offset + 30 + name_len + extra_len


def main():
    with open(sys.argv[1], 'rb') as f:
        z = zipfile.ZipFile(f)
        paths = members(z)
        if len(sys.argv) == 2:
            for role, path in paths.items():
                info = z.getinfo(path)
                stored = info.compress_type == zipfile.ZIP_STORED
                print(role, data_offset(f, info) if stored else 0, info.file_size, int(stored), path)
            return
        role, dest = sys.argv[2:4]
        info = z.getinfo(paths[role])
        with z.open(info) as src, open(dest, 'r+b' if dest.startswith('/dev/') else 'wb') as dst:
            shutil.copyfileobj(src, dst, 4 << 20)


if __name__ == '__main__':
    main()
