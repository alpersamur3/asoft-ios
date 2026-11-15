# Copy of the Android app repo's setup/phone/test/ipa_place_test.py (rc-0.1.6, bc272aa); run by test/run.py in a mirror of that layout.
"""WSL test of ipa-place.py with a fake root: run as root (it needs /work and lchown):
MSYS_NO_PATHCONV=1 wsl -u root -e python3 /mnt/d/.../setup/phone/test/ipa_place_test.py
"""
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
PLACE = os.path.join(HERE, '..', 'ipa-place.py')


def make_ipa(path, app='Game.app', bid='com.rovio.baba', ver='26.7.2'):
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr('Payload/%s/Info.plist' % app,
                   plistlib.dumps({'CFBundleIdentifier': bid, 'CFBundleShortVersionString': ver}, fmt=plistlib.FMT_BINARY))
        z.writestr('Payload/%s/Game' % app, b'x' * 100)


def put_app(root, app, plist=None, fmt=plistlib.FMT_BINARY, mark=False):
    d = os.path.join(root, 'Applications', app)
    os.makedirs(d)
    if plist is not None:
        with open(os.path.join(d, 'Info.plist'), 'wb') as f:
            f.write(plistlib.dumps(plist, fmt=fmt))
    if mark:
        open(os.path.join(d, '.asoft-ipa'), 'w').write('old.ipa\n')
    open(os.path.join(d, 'old-file'), 'w').write('old')
    return d


def run(root, ipa):
    os.makedirs('/work', exist_ok=True)
    for n in ('ipa.new', 'ipa.name'):
        if os.path.exists('/work/' + n):
            os.remove('/work/' + n)
    r = subprocess.run([sys.executable, '-I', PLACE, ipa, root, 'test.ipa'], capture_output=True, text=True)
    new = open('/work/ipa.new').read() if os.path.exists('/work/ipa.new') else None
    return r.returncode, r.stdout, new


def swap(root):
    r = subprocess.run([sys.executable, '-I', PLACE, '--swap', root, 'Game.app'], capture_output=True, text=True)
    return r.returncode


bad = 0


def check(name, cond):
    global bad
    print(('ok   ' if cond else 'FAIL ') + name)
    if not cond:
        bad += 1


tmp = tempfile.mkdtemp()
ipa = os.path.join(tmp, 'a.ipa')
make_ipa(ipa)


def fresh():
    r = tempfile.mkdtemp(dir=tmp)
    os.makedirs(os.path.join(r, 'Applications'))
    return r


r = fresh()
rc, out, new = run(r, ipa)
check('new app is staged, not yet in /Applications; ipa-new 1', rc == 0 and new == '1' and 'ipa-replaced' not in out
      and os.path.exists(r + '/Applications/.asoft-stage/Game.app/.asoft-ipa') and not os.path.exists(r + '/Applications/Game.app'))
check('  the swap puts it in place and removes the staging folder', swap(r) == 0 and os.path.exists(r + '/Applications/Game.app/.asoft-ipa')
      and not os.path.exists(r + '/Applications/.asoft-stage'))

r = fresh()
d = put_app(r, 'Game.app', {'CFBundleIdentifier': 'com.old.game', 'CFBundleShortVersionString': '1.0'})
rc, out, new = run(r, ipa)
check('unmarked third-party app: the old one stays until the swap', rc == 0 and os.path.exists(d + '/old-file'))
check('  after the swap it is replaced and marked', swap(r) == 0 and not os.path.exists(d + '/old-file') and os.path.exists(d + '/.asoft-ipa'))
check('  other id: counts as new, says what was replaced',
      new == '1' and 'ASOFT: ipa-replaced Game.app com.old.game 1.0' in out)

r = fresh()
d = put_app(r, 'Game.app', {'CFBundleIdentifier': 'com.rovio.baba', 'CFBundleShortVersionString': '25.0'}, fmt=plistlib.FMT_XML)
rc, out, new = run(r, ipa)
check('unmarked, same id (XML plist): ipa-new 0', rc == 0 and new == '0' and 'com.rovio.baba 25.0' in out and swap(r) == 0)

r = fresh()
d = put_app(r, 'Game.app', {'CFBundleIdentifier': 'com.rovio.baba'}, mark=True)
rc, out, new = run(r, ipa)
check('marked app replaced, ipa-new 0', rc == 0 and new == '0' and swap(r) == 0 and not os.path.exists(d + '/old-file'))

r = fresh()
d = put_app(r, 'Game.app', None, mark=True)
rc, out, new = run(r, ipa)
check('marked app without a plist replaced, ipa-new 0', rc == 0 and new == '0' and swap(r) == 0)

r = fresh()
d = put_app(r, 'Game.app', {'CFBundleIdentifier': 'com.apple.Game'})
rc, out, new = run(r, ipa)
check('com.apple.* app refused, untouched', rc == 2 and 'cannot replace it' in out and os.path.exists(d + '/old-file'))

r = fresh()
d = put_app(r, 'Game.app', None)
rc, out, new = run(r, ipa)
check('plist-less folder refused, untouched', rc == 2 and 'cannot replace it' in out and os.path.exists(d + '/old-file'))

r = fresh()
d = put_app(r, 'Game.app', None)
open(d + '/Info.plist', 'wb').write(b'garbage')
rc, out, new = run(r, ipa)
check('unreadable plist refused', rc == 2 and 'cannot replace it' in out)

# a staged app dropped (the job failed later): the old one is as it was, no staging folder
r = fresh()
d = put_app(r, 'Game.app', {'CFBundleIdentifier': 'com.old.game'})
rc, out, new = run(r, ipa)
subprocess.run([sys.executable, '-I', PLACE, '--drop', r])
check('drop: old app untouched, staging gone', rc == 0 and os.path.exists(d + '/old-file') and not os.path.exists(r + '/Applications/.asoft-stage'))

# a swap cut between its two renames: the next placing brings the old app back first
r = fresh()
d = put_app(r, 'Game.app', {'CFBundleIdentifier': 'com.old.game'})
os.makedirs(r + '/Applications/.asoft-stage')
os.rename(d, r + '/Applications/.asoft-stage/old-Game.app')
rc, out, new = run(r, ipa)
check('recover: a cut swap gives the old app back before the new placing', rc == 0 and 'ipa-replaced Game.app com.old.game' in out)

shutil.rmtree(tmp, ignore_errors=True)
print('failures:', bad)
sys.exit(1 if bad else 0)
