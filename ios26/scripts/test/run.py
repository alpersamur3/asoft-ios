"""Runs the phone's own tests of the .ipa signing and placing code that ios26/scripts carries a copy of
(adhoc.py, ipa-hashes.py, ipa-place.py), unchanged, in a mirror of the Android app repo's layout (the tests look for
cdhash.py and the code by those paths).

    python -I run.py        adhoc_test.py (any Python); ipa_place_test.py as well when run as root (WSL: wsl -u root)
    ASOFT_AB2=<folder of an extracted .app> python -I run.py     adds the real files of that app to adhoc_test.py

Exit 0 when every test passed.
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.dirname(HERE)
tmp = tempfile.mkdtemp(prefix='ipa-tests-')
try:
    phone = os.path.join(tmp, 'setup', 'phone')
    os.makedirs(os.path.join(phone, 'test'))
    assets = os.path.join(tmp, 'app', 'src', 'main', 'assets', 'setup', 'scripts', 'ios26')
    os.makedirs(assets)
    for n in ('adhoc.py', 'ipa-hashes.py', 'ipa-place.py'):
        shutil.copy(os.path.join(SCRIPTS, n), phone)
    for n in ('adhoc_test.py', 'ipa_place_test.py'):
        shutil.copy(os.path.join(HERE, n), os.path.join(phone, 'test'))
    for n in ('cdhash.py', 'mktc.py', 'noget.py'):
        shutil.copy(os.path.join(SCRIPTS, n), assets)
    runs = ['adhoc_test.py']
    if hasattr(os, 'geteuid') and os.geteuid() == 0:
        runs.append('ipa_place_test.py')
    else:
        print('ipa_place_test.py skipped: it needs root (it uses /work and lchown)')
    bad = 0
    for t in runs:
        r = subprocess.run([sys.executable, '-I', os.path.join(phone, 'test', t)], capture_output=True, text=True)
        out = r.stdout + r.stderr
        oks = sum(1 for l in out.splitlines() if l.startswith('ok'))
        fails = [l for l in out.splitlines() if l.startswith('FAIL')]
        print('%s: exit %d, %d ok, %d FAIL' % (t, r.returncode, oks, len(fails)))
        for l in fails:
            print('  ' + l)
        if r.returncode or fails:
            bad += 1
            print(out[-1500:])
    sys.exit(1 if bad else 0)
finally:
    shutil.rmtree(tmp, ignore_errors=True)
