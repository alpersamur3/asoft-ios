# Copy of the Android app repo's setup/phone/ipa-place.py (branch rc-0.1.6, bc272aa): that is the source of truth, change it there and
# copy it again, not here. The PC installer (Install-Ipa.ps1) and the phone sign and place an .ipa with the same code.
"""ipa-place.py IPA ROOT [NAME]: put the .app of an .ipa into /Applications of the iOS 26 disk mounted at ROOT.

The phone's counterpart of the PC's Install-Ipa.ps1 placing step (copy the .app, owner root, the folder
root:wheel 0775, every file 0777 as the PC's WSL copy leaves them). The .ipa is read straight from the disk the
host handed over (a zip followed by zeros up to a whole sector, which zipfile accepts), so nothing is copied
through RAM. Prints "ASOFT: ipa-app NAME BUNDLEID" and "ASOFT: ipa-new 1|0" (0: that app was there already: its
files are replaced, LaunchServices knows it), and writes NAME to /work/ipa.name and 1|0 to /work/ipa.new.

An app of the same folder name that is already there is replaced, unless it is a system app: no .asoft-ipa mark (which
an earlier placing here leaves) and an Info.plist (binary or XML) that names a CFBundleIdentifier starting with com.apple.
or cannot be read. An unmarked third-party app (put there by hand, or by a placing before the mark existed) is replaced
like a marked one and gets the mark. It counts as NEW for LaunchServices (ipa-new 1) unless the old and the new
CFBundleIdentifier are equal; "ASOFT: ipa-replaced NAME OLDID OLDVERSION" says what was replaced.
The new app is made in a staging folder (ROOT/Applications/.asoft-stage/NAME.app); the app that is there is only
replaced by "ipa-place.py --swap ROOT NAME" once the job has prepared the new one completely (signatures, trust cache),
and "ipa-place.py --drop ROOT" takes the staging folder away. A job that fails anywhere before the swap leaves the disk
as it was.
Refused with a plain message: no Payload/*.app, a name that leaves the app folder, not enough room on the disk.
"""
import os
import plistlib
import shutil
import stat
import sys
import zipfile


# a file in the placed app: what an earlier placing here made (a reinstall may replace it)
MARK = '.asoft-ipa'


# the app folder being made: a failure takes the half-made one away (it has no mark, so a retry would be refused)
partial = []


def fail(msg):
    print('ASOFT: ipa-fail ' + msg)
    for p in partial:
        shutil.rmtree(p, ignore_errors=True)
    sys.exit(2)


def read_plist(path):
    """The Info.plist at PATH (binary or XML) as a dict, None when it is missing or unreadable."""
    try:
        with open(path, 'rb') as f:
            d = plistlib.load(f)
        return d if isinstance(d, dict) else None
    except Exception:
        return None


STAGE = '.asoft-stage'


def swap(root, app):
    """The staged app takes the place of the one that is there: the old one is moved aside first, so a failure
    between the two renames still leaves a whole app, then it goes."""
    apps = os.path.join(root, 'Applications')
    stage = os.path.join(apps, STAGE)
    new, final, old = os.path.join(stage, app), os.path.join(apps, app), os.path.join(stage, 'old-' + app)
    if not os.path.isdir(new):
        fail('the prepared app is not there to put in place')
    if os.path.lexists(final):
        os.rename(final, old)
    os.rename(new, final)
    shutil.rmtree(stage)


def recover(root):
    """A swap that was cut between its two renames left the old app in the staging folder: it comes back first."""
    apps = os.path.join(root, 'Applications')
    stage = os.path.join(apps, STAGE)
    if os.path.isdir(stage):
        for n in os.listdir(stage):
            if n.startswith('old-') and not os.path.lexists(os.path.join(apps, n[4:])):
                os.rename(os.path.join(stage, n), os.path.join(apps, n[4:]))


def main():
    if len(sys.argv) > 3 and sys.argv[1] == '--swap':
        swap(sys.argv[2], sys.argv[3])
        return
    if len(sys.argv) > 2 and sys.argv[1] == '--drop':
        shutil.rmtree(os.path.join(sys.argv[2], 'Applications', STAGE), ignore_errors=True)
        return
    ipa, root = sys.argv[1], sys.argv[2]
    ipa_name = sys.argv[3] if len(sys.argv) > 3 else ''
    try:
        z = zipfile.ZipFile(ipa)
    except (zipfile.BadZipFile, OSError) as e:
        fail('this file is not a readable .ipa (%s)' % e)
    names = z.namelist()
    # the first Payload/NAME.app
    app = None
    for n in names:
        parts = n.split('/')
        if len(parts) >= 3 and parts[0] == 'Payload' and parts[1].endswith('.app'):
            app = parts[1]
            break
    if app is None:
        fail('there is no app (Payload/NAME.app) in this .ipa')
    prefix = 'Payload/' + app + '/'
    members = [i for i in z.infolist() if i.filename.startswith(prefix) and i.filename != prefix]
    total = sum(i.file_size for i in members)
    st = os.statvfs(root)
    free = st.f_bavail * st.f_frsize
    # (the app's own files, then what the guest writes on first start)
    if total + (256 << 20) > free:
        fail('iOS 26\'s disk has %d MB free and this app needs %d MB' % (free >> 20, total >> 20))

    bundle_id = ''
    info = prefix + 'Info.plist'
    if info in names:
        try:
            bundle_id = str(plistlib.loads(z.read(info)).get('CFBundleIdentifier', ''))
        except Exception:
            bundle_id = ''
    print('ASOFT: ipa-app %s %s' % (app, bundle_id or '?'))

    recover(root)
    dst = os.path.join(root, 'Applications', app)
    new = 1
    if os.path.lexists(dst):
        old = read_plist(os.path.join(dst, 'Info.plist'))
        old_id = str(old.get('CFBundleIdentifier', '')) if old else ''
        marked = os.path.exists(os.path.join(dst, MARK))
        # a system app of the same name is never replaced
        if not marked and (not old_id or old_id.startswith('com.apple.')):
            fail('iOS 26 has an app called %s of its own; this .ipa cannot replace it' % app)
        # LaunchServices knows the app as it is only when its id stays the same
        # (a marked app whose plist cannot be read was ours: as before, the same app)
        new = 0 if (old_id and old_id == bundle_id) or (marked and not old_id) else 1
        ver = str((old or {}).get('CFBundleShortVersionString') or (old or {}).get('CFBundleVersion') or '?')
        print('ASOFT: ipa-replaced %s %s %s' % (app, old_id or '?', ver))
    print('ASOFT: ipa-new %d' % new)
    with open('/work/ipa.new', 'w') as f:
        f.write(str(new))
    # (a staging folder an earlier job left goes; the app that is there stays until the swap)
    stage = os.path.join(root, 'Applications', STAGE)
    shutil.rmtree(stage, ignore_errors=True)
    dst = os.path.join(stage, app)
    partial.append(stage)
    # the mark first
    os.makedirs(dst)
    with open(os.path.join(dst, MARK), 'w') as f:
        f.write(ipa_name + '\n')
    base = os.path.realpath(dst)
    done = 0
    for i in members:
        rel = i.filename[len(prefix):]
        target = os.path.realpath(os.path.join(dst, rel))
        if target != base and not target.startswith(base + os.sep):
            fail('a file name in this .ipa leaves the app folder: ' + i.filename)
        if i.is_dir():
            os.makedirs(target, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(target), exist_ok=True)
        mode = (i.external_attr >> 16) & 0xFFFF
        if stat.S_ISLNK(mode):
            os.symlink(z.read(i).decode('utf-8'), os.path.join(dst, rel))
        else:
            with z.open(i) as src, open(target, 'wb') as out:
                shutil.copyfileobj(src, out, 1 << 20)
            os.chmod(target, 0o777)
        done += i.file_size
    # the same owner and modes as the PC's placing: root, the app folder root:wheel (group 80) 0775
    for d, dirs, files in os.walk(dst):
        for n in dirs + files:
            p = os.path.join(d, n)
            os.lchown(p, 0, 0)
            if os.path.isdir(p) and not os.path.islink(p):
                os.chmod(p, 0o777)
    os.chown(dst, 0, 80)
    os.chmod(dst, 0o775)
    partial.clear()
    with open('/work/ipa.name', 'w') as f:
        f.write(app)
    print('ASOFT: progress 55 placed %s (%d MB)' % (app, done >> 20))


try:
    main()
except OSError as e:
    fail('could not place the app: %s' % e)
