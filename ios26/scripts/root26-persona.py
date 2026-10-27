#!/usr/bin/env python3
"""M2 persona fix: write the mobile user's persona set into the usermanagerd
persona manifest (/private/var/keybags/persona.kb), the record a restore /
first boot would leave behind.

usermanagerd's early boot task does create the user's personas (kernel
persona 200 = Default exists), but saving the manifest goes through
-[UMFilesystemProvider atomicallyWriteData:toPath:error:], which swaps the
temp file in with renamex_np(RENAME_SWAP). HFS+ (our Data volume) has no
swap: ENOTSUP, and only ENOENT falls back to rename(). So the first write
(system session personas) lands and every later one fails; the daemon then
loads a manifest without the user ("no personas found for user ...") and
lsd's PRIMARY persona container query comes back empty.

With the user's entry already in the manifest, the boot task skips creating
it and just loads those personas into the kernel ("setup kernel personas"),
and the daemon sees the same set. Values are what usermanagerd generates
(sub_1000902ac / sub_10008ead0 / sub_10008e6e4): unique string
FEEDEEEE-DDDD-CCCC-BBBB-<0000|3333|5555><uid:%08X>, IDs = first free in
[1000,2000) / [99,199) / [199,299) after the system session's 99 and 199.
Universal (type 4, no kernel persona) is left out unless --universal.

Run as root on the mounted root with the Data volume on private/var:

  root26-persona.py MOUNTED_ROOT on [--universal]|off

Reversible: backs up persona.kb to persona.kb.prepersona. Idempotent.
"""
import os, plistlib, shutil, sys

PREFIX = 'FEEDEEEE-DDDD-CCCC-BBBB-'
SYSTEM_BUNDLES = sorted(['com.apple.mobilenotes', 'com.apple.Preferences', 'com.apple.siri',
                         'com.apple.mobilemail', 'com.apple.DocumentsApp',
                         'com.apple.CloudKit.ShareBear'])
UNIVERSAL_BUNDLES = sorted(['com.apple.mobilenotes', 'com.apple.mobilecal'])


def foreground_session(kb):
    """(uuid, uid) of the booted user session in usersession.kb."""
    with open(kb, 'rb') as f:
        d = plistlib.load(f)
    blob = plistlib.loads(d['BLOB'])
    sessions = blob if isinstance(blob, list) else [blob]
    booted = d.get('BOOTEDUSER', 501)
    for s in sessions:
        if s.get('MKBUserSessionID') == booted:
            return s['MKBUserSessionUUID'], s['MKBUserSessionID']
    sys.exit('no session for BOOTEDUSER %r in %s' % (booted, kb))


def user_personas(uuid, uid, universal):
    def p(ptype, pid, nick, tag, bundles=None):
        d = {'UserPersonaType': ptype, 'UserPersonaNickName': nick, 'UserPersonaUserODUUID': uuid}
        if pid is not None:
            d['UserPersonaID'] = pid
        if tag is not None:
            d['UserPersonaUniqueString'] = '%s%s%08X' % (PREFIX, tag, uid)
        if bundles:
            d['UserPersonaBundleIDS'] = bundles
        return d
    # creation order of sub_10008fb30: Personal, System, Default, Universal
    out = [p(0, 1000, 'Personal', '0000'),
           p(3, 100, 'System', '3333', SYSTEM_BUNDLES),
           p(5, 200, 'Default', '5555')]
    if universal:
        out.append(p(4, None, 'Universal', None, UNIVERSAL_BUNDLES))
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    root, mode = sys.argv[1], sys.argv[2]
    kb = os.path.join(root, 'private/var/keybags')
    path = os.path.join(kb, 'persona.kb')
    pre = path + '.prepersona'
    if mode == 'off':
        if not os.path.exists(pre):
            sys.exit('no .prepersona backup to restore')
        shutil.copy2(pre, path)
        print('restored persona.kb from .prepersona')
        return
    if mode != 'on':
        sys.exit(__doc__)
    if not os.path.exists(pre):
        shutil.copy2(path, pre)
    with open(pre, 'rb') as f:
        manifest = plistlib.load(f)
    uuid, uid = foreground_session(os.path.join(kb, 'usersession.kb'))
    personas = user_personas(uuid, uid, '--universal' in sys.argv[3:])
    entry = {'BLOB': plistlib.dumps(personas, fmt=plistlib.FMT_BINARY), 'NUMENT': len(personas)}
    manifest['UserPersonaDictionary'][uuid] = plistlib.dumps(entry, fmt=plistlib.FMT_BINARY)
    manifest['UsePersonaGenerationID'] = manifest.get('UsePersonaGenerationID', 1) + 1
    st = os.stat(pre)
    tmp = path + '.new'
    with open(tmp, 'wb') as f:
        plistlib.dump(manifest, f, fmt=plistlib.FMT_BINARY)
    os.chown(tmp, st.st_uid, st.st_gid)
    os.chmod(tmp, st.st_mode & 0o7777)
    os.replace(tmp, path)
    print('persona.kb: %d user(s), generation %d; added %s (uid %d):' % (
        len(manifest['UserPersonaDictionary']), manifest['UsePersonaGenerationID'], uuid, uid))
    for d in personas:
        print('  type %d id %s %s %s' % (d['UserPersonaType'], d.get('UserPersonaID'),
                                       d['UserPersonaNickName'], d.get('UserPersonaUniqueString')))


if __name__ == '__main__':
    main()
