# Copy of the Android app repo's setup/phone/ipa-hashes.py (branch rc-0.1.6, bc272aa): that is the source of truth, change it there and
# copy it again, not here. The PC installer (Install-Ipa.ps1) and the phone sign and place an .ipa with the same code.
"""ipa-hashes.py SCRIPTS APP OUT [ENTS]: the CDHashes of every Mach-O of an app for the trust cache, after making each usable.

SCRIPTS is the folder with cdhash.py (the PC installer's), APP the staged .app, OUT the list (one 40-digit hash a
line, the form mktc.py reads). Every 64-bit slice is first signed ad hoc with one SHA-256 code directory of our own (adhoc.py, next to this file; a
foreign signature is never trusted, even one that looks usable); each file is named: "ASOFT: ipa-signed PATH REASON" and,
when a library's entitlements were left out, "ASOFT: ipa-ents-dropped PATH N". A file adhoc.py cannot sign makes the job
fail ("ASOFT: ipa-fail PATH: why", exit 4), and so does a slice that does not end with exactly one SHA-256 directory
whose CDHash is in the list (exit 3): an app with one such file does not start, so none is installed. The count line is
"ASOFT: ipa-hashes N MACHOS".
"""
import os
import struct
import sys

scripts, app, out = sys.argv[1], sys.argv[2], sys.argv[3]
# ENTS (optional): a file, one entitlement a line, that every main executable gets as true (a test knob, see adhoc.py)
add_ents = []
if len(sys.argv) > 4 and os.path.isfile(sys.argv[4]):
    with open(sys.argv[4]) as f:
        add_ents = [l.strip() for l in f if l.strip()]
sys.path.insert(0, scripts)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import adhoc  # noqa: E402  (next to this file)
import cdhash  # noqa: E402  (the PC installer's, from SCRIPTS)


def fail(rel, why, code):
    print('ASOFT: ipa-fail %s: %s' % (rel, why))
    sys.exit(code)


hashes = set()
machos = 0
for p in adhoc.machos(app):
    rel = os.path.relpath(p, app)
    try:
        for why, got, dropped in adhoc.resign(p, app, add_exec_entitlements=add_ents):
            print('ASOFT: ipa-signed %s %s' % (rel, why.replace(' ', '_')))
            if dropped:
                print('ASOFT: ipa-ents-dropped %s %d' % (rel, dropped))
    except (adhoc.Unsupported, struct.error, OSError) as e:
        fail(rel, 'cannot be given a signature iOS 26 accepts: %s' % e, 4)
    with open(p, 'rb') as f:
        buf = f.read()
    try:
        arches = adhoc.fat_arches(buf)
    except adhoc.Unsupported:
        continue                                    # not a Mach-O (a Java class has a fat magic)
    slices = [buf] if arches is None and adhoc.is_64(buf, 0) else \
        [buf[o:o + s] for _, _, o, s, _ in (arches or []) if adhoc.is_64(buf, o)]
    if not slices:
        print('ASOFT: ipa-warn %s has no 64-bit code: iOS 26 cannot run it' % rel)
        continue
    machos += 1
    for sl in slices:
        got = [h for h, _flags in cdhash.cdhashes(sl)]
        ok, why = adhoc.usable(sl)
        cds = adhoc.directories(sl, adhoc.blobs(sl, adhoc.Info(sl)))
        if not ok or len(got) != 1 or len(cds) != 1:
            fail(rel, 'does not end with exactly one usable code directory (%s, %d hashes)' % (why or 'ok', len(got)), 3)
        hashes.update(got)
with open(out, 'w') as f:
    f.write('\n'.join(sorted(hashes)) + ('\n' if hashes else ''))
print('ASOFT: ipa-hashes %d %d' % (len(hashes), machos))
