# Copy of the Android app repo's setup/phone/test/adhoc_test.py (rc-0.1.6, bc272aa); run by test/run.py in a mirror of that layout.
"""Tests of adhoc.py and ipa-hashes.py on made-up Mach-O files, and (when ASOFT_AB2 names a folder holding the extracted
Angry Birds 2 .app, see below) on its two real files. No root needed:
    python3 -I adhoc_test.py            (WSL or Windows)
    ASOFT_AB2=/path/to/Payload/AngryBirds2.app python3 -I adhoc_test.py

The checker here (`slice_state`) is written apart from adhoc.py: it reads the signature again from the bytes and compares
every page hash, so it stands in for the guest's page validation (not for AMFI's own decision, which only a boot shows).
"""
import hashlib
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import adhoc  # noqa: E402

PY = sys.executable
bad = 0


def check(name, cond):
    global bad
    print(('ok   ' if cond else 'FAIL ') + name)
    if not cond:
        bad += 1


def expect_unsupported(name, fn, word):
    try:
        fn()
    except adhoc.Unsupported as e:
        check(name + ' (%s)' % e, word in str(e))
        return
    check(name + ' (no error)', False)


# -- fixtures

def macho(filetype=6, sig_len=None, sig=None, cryptid=None, room=True, junk_after=b'', ncode=4):
    """A thin arm64 Mach-O: __TEXT over ncode pages (the load commands at the top, one section at 0x1000 when there is
    room, else right after the commands), __LINKEDIT, and when sig_len (or sig) is given a signature area at its end."""
    if sig is not None:
        sig_len = len(sig)
    text_len = 0x1000 * ncode
    text = bytearray(os.urandom(text_len))
    text[:0x200] = bytes(0x200)
    link = b'LINKEDIT-DATA' * 4
    sect = struct.pack('<16s16sQQIIIIIIII', b'__text', b'__TEXT', 0x1000, 0x100, 0x1000 if room else 256, 0, 0, 0, 0, 0, 0, 0)
    cmds = [struct.pack('<II16sQQQQiiII', 0x19, 72 + 80, b'__TEXT', 0, text_len, 0, text_len, 5, 5, 1, 0) + sect]
    sig_at = text_len + len(link)
    sig_at += -sig_at % 16
    le_size = (sig_at - text_len) + (sig_len or 0)
    cmds.append(struct.pack('<II16sQQQQiiII', 0x19, 72, b'__LINKEDIT', text_len, 0x4000, text_len, le_size if sig_len else len(link), 1, 1, 0, 0))
    if cryptid is not None:
        cmds.append(struct.pack('<IIIIII', 0x2c, 24, 0x1000, 0x1000, cryptid, 0))
    if sig_len:
        cmds.append(struct.pack('<IIII', 0x1d, 16, sig_at, sig_len))
    body = b''.join(cmds)
    text[:32 + len(body)] = struct.pack('<IiiIIIII', 0xfeedfacf, 0x100000c, 0, filetype, len(cmds), len(body), 0, 0) + body
    out = bytes(text) + link
    if sig_len:
        out += bytes(sig_at - len(out))
        out += sig if sig is not None else bytes(sig_len)
    return out + junk_after


def old_sig(m, htype, ents=None, ident=b'old.ident', specials4=False):
    """A signature made apart from adhoc.py: a code directory of @htype over @m (the file up to the signature)."""
    hf = hashlib.sha1 if htype == 1 else hashlib.sha256
    hs = hf().digest_size
    n = (len(m) + 4095) // 4096
    req = struct.pack('>III', 0xfade0c01, 12, 0)
    ent = struct.pack('>II', 0xfade7171, 8 + len(ents)) + ents if ents else None
    specials = {2: hf(req).digest()}
    nsp = 2
    if ent:
        specials[5] = hf(ent).digest()
        nsp = 5
    if specials4:
        specials[4] = hf(b'x').digest()
        nsp = max(nsp, 5)
    hoff = 44 + len(ident) + 1 + hs * nsp
    cd = struct.pack('>IIIIIIIIIBBBB', 0xfade0c02, hoff + hs * n, 0x20001, 0, hoff, 44, nsp, n, len(m), hs, htype, 0, 12)
    cd += struct.pack('>I', 0) + ident + b'\0'
    for s in range(nsp, 0, -1):
        cd += specials.get(s, bytes(hs))
    for p in range(n):
        cd += hf(m[p * 4096:min((p + 1) * 4096, len(m))]).digest()
    parts = [(0, cd), (2, req)] + ([(5, ent)] if ent else [])
    index, at = b'', 12 + 8 * len(parts)
    for slot, x in parts:
        index += struct.pack('>II', slot, at)
        at += len(x)
    body = index + b''.join(x for _, x in parts)
    return struct.pack('>III', 0xfade0cc0, 12 + len(body), len(parts)) + body


def signed(htype=1, ents=None, specials4=False, **kw):
    """A Mach-O with a signature that matches its pages (the header already counts the signature's size)."""
    L = len(old_sig(bytes(0x1000 * kw.get('ncode', 4) + 64), htype, ents, specials4=specials4))
    m = macho(sig_len=L, **{k: v for k, v in kw.items() if k != 'junk_after'})
    sig_at = len(m) - L
    return m[:sig_at] + old_sig(m[:sig_at], htype, ents, specials4=specials4) + kw.get('junk_after', b'')


def slice_state(m):
    """(has a SHA-256 CD, all its page hashes match, cdhash hex) read again from the bytes."""
    n = struct.unpack_from('<I', m, 16)[0]
    o = 32
    so = ss = None
    for _ in range(n):
        c, s = struct.unpack_from('<II', m, o)
        if c == 0x1d:
            so, ss = struct.unpack_from('<II', m, o + 8)
        o += s
    if so is None:
        return False, False, ''
    _, _, cnt = struct.unpack_from('>III', m, so)
    for i in range(cnt):
        _, off = struct.unpack_from('>II', m, so + 12 + 8 * i)
        at = so + off
        magic, ln = struct.unpack_from('>II', m, at)
        if magic != 0xfade0c02:
            continue
        ver, flags, hoff, ioff, nsp, ncode, limit, hsize, htype, plat, psize = struct.unpack_from('>IIIIIIIBBBB', m, at + 8)
        if htype != 2:
            continue
        ok = limit <= len(m) and ncode == (limit + (1 << psize) - 1) // (1 << psize)
        for p in range(ncode):
            d = hashlib.sha256(m[p * 4096:min((p + 1) * 4096, limit)]).digest()
            ok = ok and d == m[at + hoff + 32 * p:at + hoff + 32 * (p + 1)]
        return True, ok, hashlib.sha256(m[at:at + ln]).hexdigest()[:40]
    return False, False, ''


def blob_at(m, slot):
    n = struct.unpack_from('<I', m, 16)[0]
    o = 32
    for _ in range(n):
        c, s = struct.unpack_from('<II', m, o)
        if c == 0x1d:
            so, ss = struct.unpack_from('<II', m, o + 8)
            _, _, cnt = struct.unpack_from('>III', m, so)
            for i in range(cnt):
                sl, off = struct.unpack_from('>II', m, so + 12 + 8 * i)
                if sl == slot:
                    ln = struct.unpack_from('>I', m, so + off + 4)[0]
                    return bytes(m[so + off:so + off + ln])
        o += s
    return None


tmp = tempfile.mkdtemp()


def put(name, data, mode=0o755):
    p = os.path.join(tmp, name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(data)
    os.chmod(p, mode)
    return p


def read(p):
    with open(p, 'rb') as f:
        return f.read()


# -- the fixtures themselves are what they say

fx = signed(1)
check('fixture: SHA-1 signed file reads as SHA-1 only', adhoc.usable(fx) == (False, 'SHA-1 only'))
check('fixture: unsigned reads as unsigned', adhoc.usable(macho()) == (False, 'unsigned'))

# -- unsigned
orig = macho()
p = put('a/unsigned.dylib', orig)
r = adhoc.resign(p, tmp)
m = read(p)
has, ok, h = slice_state(m)
check('unsigned: signed, SHA-256 directory, every page matches', has and ok and r and r[0][1] == [h] and r[0][0] == 'unsigned')
check('unsigned: the pages after the header are the original ones', m[0x1000:0x4000] == orig[0x1000:0x4000])
check('unsigned: signing again gives the same file (deterministic)', adhoc.resign(p, tmp) and read(p) == m)

# -- SHA-1 only, with entitlements (XML only: the DER one is made) and an identifier to keep
ents = plistlib.dumps({'com.apple.security.app-sandbox': False, 'keychain-access-groups': ['a.b'], 'n': 3}, fmt=plistlib.FMT_XML)
p = put('a/sha1.dylib', signed(1, ents=ents, filetype=2))        # an executable keeps its entitlements
old = read(p)
r = adhoc.resign(p, tmp)
m = read(p)
has, ok, h = slice_state(m)
check('SHA-1 only: re-signed with SHA-256, pages match', r and r[0][0] == 'SHA-1 only' and has and ok and r[0][1] == [h])
check('SHA-1 only: entitlements XML kept byte for byte', blob_at(m, 5) == blob_at(old, 5) and blob_at(m, 5) is not None)
check('SHA-1 only: a DER entitlements blob was made', (blob_at(m, 7) or b'')[:4] == bytes.fromhex('fade7172'))
cd0 = blob_at(m, 0)
io = struct.unpack_from('>I', cd0, 20)[0]
check('SHA-1 only: the identifier stays', cd0[io:cd0.index(b'\0', io)] == b'old.ident')
cdhash_cmd = subprocess.run([PY, '-I', os.path.join(HERE, '..', '..', '..', 'app', 'src', 'main', 'assets', 'setup', 'scripts', 'ios26', 'cdhash.py'), p],
                            capture_output=True, text=True).stdout if os.path.exists(os.path.join(HERE, '..', '..', '..', 'app', 'src', 'main', 'assets', 'setup', 'scripts', 'ios26', 'cdhash.py')) else None
if cdhash_cmd is not None:
    check('SHA-1 only: cdhash.py (the trust cache route) reads the same CDHash', cdhash_cmd.split()[0] == h)

# -- a library's entitlements are left out (a process gets its own from the main executable; AMFI refuses restricted ones)
rest = plistlib.dumps({'platform-application': True, 'com.apple.private.security.no-container': True}, fmt=plistlib.FMT_XML)
p = put('a/lib-with-ents.dylib', signed(2, ents=rest))
r = adhoc.resign(p, tmp)
m = read(p)
has, ok, h = slice_state(m)
check('library: signed, its 2 restricted entitlements left out, no slot 5 or 7', has and ok and r[0][2] == 2
      and blob_at(m, 5) is None and blob_at(m, 7) is None)
p = put('a/lib-keep.dylib', signed(2, ents=rest))
adhoc.resign(p, tmp, keep_library_entitlements=True)
check('library: --keep-library-entitlements keeps them', blob_at(read(p), 5) is not None and blob_at(read(p), 7) is not None)

# -- --add-exec-entitlement: only a main executable gets the key (XML and DER, slots 5 and 7 hashed again), nothing by default
KEY = 'com.apple.private.set-exception-port'
base_ents = plistlib.dumps({'application-identifier': 'T.app'}, fmt=plistlib.FMT_XML)
p = put('a/exe-add', signed(2, ents=base_ents, filetype=2))
adhoc.resign(p, tmp, add_exec_entitlements=[KEY])
m = read(p)
x = plistlib.loads(blob_at(m, 5)[8:])
cd0 = blob_at(m, 0)
hoff = struct.unpack_from('>I', cd0, 16)[0]
check('exec entitlement added: XML has both keys, DER blob made, slots 5 and 7 match their blobs',
      x == {'application-identifier': 'T.app', KEY: True} and blob_at(m, 7) is not None
      and cd0[hoff - 32 * 5:hoff - 32 * 4] == hashlib.sha256(blob_at(m, 5)).digest()
      and cd0[hoff - 32 * 7:hoff - 32 * 6] == hashlib.sha256(blob_at(m, 7)).digest()
      and KEY.encode() in blob_at(m, 7) and slice_state(m)[:2] == (True, True))
p = put('a/exe-none', signed(2, ents=base_ents, filetype=2))
adhoc.resign(p, tmp)
check('exec entitlement: none added by default', plistlib.loads(blob_at(read(p), 5)[8:]) == {'application-identifier': 'T.app'})
p = put('a/lib-noadd.dylib', signed(2, ents=base_ents))
adhoc.resign(p, tmp, add_exec_entitlements=[KEY])
check('exec entitlement: a library gets none', blob_at(read(p), 5) is None)
p = put('a/exe-noents', signed(2, filetype=2))
adhoc.resign(p, tmp, add_exec_entitlements=[KEY])
check('exec entitlement: an executable without any gets just it', plistlib.loads(blob_at(read(p), 5)[8:]) == {KEY: True})

# -- bad pages: a SHA-256 signature whose code pages no longer match (a decrypted binary)
good = bytearray(signed(2))
check('a matching SHA-256 file reads as usable', adhoc.usable(bytes(good))[0])
good[0x2100] ^= 0xff
p = put('a/badpages.dylib', bytes(good))
check('bad pages: seen as unusable', adhoc.usable(bytes(good)) == (False, 'its code pages do not match its signature'))
r = adhoc.resign(p, tmp)
m = read(p)
has, ok, h = slice_state(m)
check('bad pages: re-signed over the file as it is', r and has and ok and m[0x2100] == good[0x2100])
p = put('a/usable.dylib', signed(2))
before = read(p)
r = adhoc.resign(p, tmp)
m = read(p)
check('usable foreign signature: signed again all the same (one SHA-256 directory of ours)',
      r and r[0][0] == 'a signature from elsewhere' and slice_state(m)[:2] == (True, True) and m != before
      and len(adhoc.directories(m, adhoc.blobs(m, adhoc.Info(m)))) == 1)
# two directories (SHA-1 primary, SHA-256 alternate, as iGameGod has): one of ours afterwards
dual = bytearray(signed(2))
p = put('a/dual.dylib', bytes(dual))
adhoc.resign(p, tmp)
m = read(p)
check('dual-directory file ends with exactly one directory', len(adhoc.directories(m, adhoc.blobs(m, adhoc.Info(m)))) == 1)

# -- a bundle's executable: special slots 1 and 3 and the identifier come from its files
b = 'bundle/Fw.framework/'
put(b + 'Info.plist', plistlib.dumps({'CFBundleExecutable': 'Fw', 'CFBundleIdentifier': 'com.x.fw'}))
put(b + '_CodeSignature/CodeResources', b'resources')
p = put(b + 'Fw', macho())
adhoc.resign(p, os.path.join(tmp, 'bundle'))
m = read(p)
cd = blob_at(m, 0)
hoff, ioff = struct.unpack_from('>II', cd, 16)
nsp = struct.unpack_from('>I', cd, 24)[0]
s1 = cd[hoff - 32 * 1:hoff]
s3 = cd[hoff - 32 * 3:hoff - 32 * 2]
check('bundle executable: slot 1 = Info.plist, slot 3 = CodeResources, identifier from the plist',
      s1 == hashlib.sha256(read(os.path.join(tmp, b + 'Info.plist'))).digest() and s3 == hashlib.sha256(b'resources').digest()
      and cd[ioff:cd.index(b'\0', ioff)] == b'com.x.fw')

# -- fat: a 32-bit slice, an unusable arm64, a usable arm64e: each slice on its own
a32 = bytearray(os.urandom(0x2000))
a32[:4] = struct.pack('<I', 0xfeedface)
s64 = macho()
s64e = signed(2)
slices_ = [(12, 9, bytes(a32), 14), (0x100000c, 0, s64, 14), (0x100000c, 2, s64e, 14)]
hdr = 8 + 20 * 3
out = bytearray(struct.pack('>II', 0xcafebabe, 3)) + bytes(hdr - 8)
pos = hdr
for i, (cpu, sub, sl, al) in enumerate(slices_):
    pos = (pos + (1 << al) - 1) & ~((1 << al) - 1)
    out += bytes(pos - len(out)) + sl
    struct.pack_into('>iiIII', out, 8 + 20 * i, cpu, sub, pos, len(sl), al)
    pos += len(sl)
p = put('a/fat.dylib', bytes(out))
r = adhoc.resign(p, tmp)
m = read(p)
arches = adhoc.fat_arches(m)
check('fat: three slices stay, header rewritten and aligned', len(arches) == 3 and all(o % (1 << al) == 0 for _, _, o, _, al in arches))
check('fat: the 32-bit slice is byte for byte the same', m[arches[0][2]:arches[0][2] + arches[0][3]] == bytes(a32))
check('fat: both 64-bit slices are signed (arm64 and arm64e), one hash each',
      all(slice_state(m[arches[k][2]:arches[k][2] + arches[k][3]])[:2] == (True, True) for k in (1, 2)) and r and len(r[0][1]) == 2)

# -- what it must refuse, naming the reason
expect_unsupported('encrypted slice refused', lambda: adhoc.sign_slice(macho(cryptid=1), adhoc.Context('x', tmp)), 'encrypted')
expect_unsupported('signature not at the end refused',
                   lambda: adhoc.sign_slice(signed(1, junk_after=b'tail-data-after-the-signature'), adhoc.Context('x', tmp)), 'not the last')
expect_unsupported('no room in the header refused', lambda: adhoc.sign_slice(macho(room=False), adhoc.Context('x', tmp)), 'no room')
expect_unsupported('LINKEDIT not at the end refused (unsigned)',
                   lambda: adhoc.sign_slice(macho() + b'extra-after-linkedit', adhoc.Context('x', tmp)), '__LINKEDIT is not at the end')
expect_unsupported('application-specific slots refused',
                   lambda: adhoc.sign_slice(signed(2, specials4=True), adhoc.Context('x', tmp)), 'application-specific')
weird = plistlib.dumps({'x': b'data-value'}, fmt=plistlib.FMT_XML)
expect_unsupported('entitlement value of an unsupported type refused', lambda: adhoc.sign_slice(signed(1, ents=weird, filetype=2), adhoc.Context('x', tmp)), 'DER')

# -- ipa-hashes.py on a made-up app: signs what it can, fails naming a file it cannot
app = os.path.join(tmp, 'App.app')
put('App.app/Main', signed(2))
put('App.app/Frameworks/Lib.dylib', macho())
put('App.app/Frameworks/Old.dylib', signed(1))
put('App.app/data.bin', os.urandom(100))
put('App.app/Classy.class', bytes.fromhex('cafebabe0000003400') + os.urandom(100))
scripts = os.path.join(HERE, '..', '..', '..', 'app', 'src', 'main', 'assets', 'setup', 'scripts', 'ios26')
if not os.path.exists(os.path.join(scripts, 'cdhash.py')):
    scripts = os.path.join(tmp, 'scripts')
    os.makedirs(scripts)
    shutil.copy(os.path.join(HERE, 'cdhash_for_test.py'), os.path.join(scripts, 'cdhash.py')) if os.path.exists(os.path.join(HERE, 'cdhash_for_test.py')) else None
if os.path.exists(os.path.join(scripts, 'cdhash.py')):
    r = subprocess.run([PY, '-I', os.path.join(HERE, '..', 'ipa-hashes.py'), scripts, app, os.path.join(tmp, 'h.txt')], capture_output=True, text=True)
    hs = [x for x in read(os.path.join(tmp, 'h.txt')).decode().split() if x]
    check('ipa-hashes: signs all three machos, three hashes', r.returncode == 0 and 'ipa-hashes 3 3' in r.stdout
          and 'ipa-signed Frameworks/Lib.dylib unsigned' in r.stdout and 'ipa-signed Frameworks/Old.dylib SHA-1_only' in r.stdout
          and 'ipa-signed Main a_signature_from_elsewhere' in r.stdout and len(hs) == 3)
    check('ipa-hashes: every listed hash is the CDHash of a SHA-256 directory that matches its file',
          sorted(hs) == sorted(slice_state(read(os.path.join(app, n)))[2] for n in ('Main', 'Frameworks/Lib.dylib', 'Frameworks/Old.dylib')))
    # every executable (the app's own, an app extension) gets set-exception-port by default, libraries none; the ENTS file
    # adds keys or leaves the default out; the log line names key and file
    exe_ents = plistlib.dumps({'application-identifier': 'T.app'}, fmt=plistlib.FMT_XML)
    def ents_of(path):
        b5 = blob_at(read(path), 5)
        return plistlib.loads(b5[8:]) if b5 else None
    def make_app(name):
        put(name + '/Game', signed(2, ents=exe_ents, filetype=2))
        put(name + '/PlugIns/Share.appex/Share', signed(2, filetype=2))
        put(name + '/Frameworks/Lib.dylib', signed(2, ents=exe_ents))
        return os.path.join(tmp, name)
    def run_hashes(a, ents_file=None):
        cmd = [PY, '-I', os.path.join(HERE, '..', 'ipa-hashes.py'), scripts, a, os.path.join(tmp, 'hh.txt')]
        if ents_file:
            w = os.path.join(tmp, 'ipa.ents')
            with open(w, 'w') as f:
                f.write(ents_file)
            cmd.append(w)
        return subprocess.run(cmd, capture_output=True, text=True)
    a = make_app('App3.app')
    r = run_hashes(a)
    check('ipa-hashes: by default the app and its extension get the exception-port key, a library none',
          r.returncode == 0 and ents_of(os.path.join(a, 'Game')) == {'application-identifier': 'T.app', KEY: True}
          and ents_of(os.path.join(a, 'PlugIns/Share.appex/Share')) == {KEY: True} and ents_of(os.path.join(a, 'Frameworks/Lib.dylib')) is None
          and 'ipa-ent Game ' + KEY in r.stdout and 'ipa-ent PlugIns/Share.appex/Share ' + KEY in r.stdout and 'ipa-ent Frameworks' not in r.stdout)
    a = make_app('App4.app')
    r = run_hashes(a, '-default\n')
    check('ipa-hashes: the ENTS line "-default" leaves the key out',
          r.returncode == 0 and ents_of(os.path.join(a, 'Game')) == {'application-identifier': 'T.app'}
          and ents_of(os.path.join(a, 'PlugIns/Share.appex/Share')) is None and 'ipa-ent ' not in r.stdout)
    a = make_app('App5.app')
    r = run_hashes(a, 'com.example.more\n')
    check('ipa-hashes: an ENTS key comes besides the default',
          r.returncode == 0 and ents_of(os.path.join(a, 'Game')) == {'application-identifier': 'T.app', KEY: True, 'com.example.more': True})
    a = make_app('App6.app')
    r = run_hashes(a, '-default\ncom.example.more\n')
    check('ipa-hashes: -default with an own key gives only that key',
          r.returncode == 0 and ents_of(os.path.join(a, 'Game')) == {'application-identifier': 'T.app', 'com.example.more': True})
    put('App2.app/Main', signed(2))
    put('App2.app/Frameworks/Enc.dylib', macho(cryptid=1))
    r = subprocess.run([PY, '-I', os.path.join(HERE, '..', 'ipa-hashes.py'), scripts, os.path.join(tmp, 'App2.app'), os.path.join(tmp, 'h2.txt')],
                       capture_output=True, text=True)
    check('ipa-hashes: an encrypted file fails the job, named (exit 4)',
          r.returncode == 4 and 'ipa-fail Frameworks/Enc.dylib' in r.stdout and 'encrypted' in r.stdout)

# -- the real files of Angry Birds 2, when asked for
ab2 = os.environ.get('ASOFT_AB2')
if ab2:
    for rel in ('Frameworks/libAngryBirds2.dylib', 'Frameworks/UnityFramework.framework/UnityFramework', 'AngryBirds2',
                'Frameworks/iGameGod.framework/iGameGod', 'Frameworks/iGameGod.framework/libswift_Concurrency.dylib',
                'Frameworks/FBAEMKit.framework/FBAEMKit', 'Frameworks/Sentry.framework/Sentry'):
        src = os.path.join(ab2, rel)
        if not os.path.isfile(src):
            print('skip (not extracted): ' + rel)
            continue
        dst = os.path.join(tmp, 'ab2', rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy(src, dst)
        for extra in ('Info.plist', '_CodeSignature/CodeResources'):
            e = os.path.join(os.path.dirname(src), extra)
            if os.path.isfile(e):
                os.makedirs(os.path.dirname(os.path.join(os.path.dirname(dst), extra)), exist_ok=True)
                shutil.copy(e, os.path.join(os.path.dirname(dst), extra))
        before = read(dst)
        why = adhoc.usable(before)
        ents_before = blob_at(before, 5)
        r = adhoc.resign(dst, os.path.join(tmp, 'ab2'))
        after = read(dst)
        has, ok, h = slice_state(after)
        cds = adhoc.directories(after, adhoc.blobs(after, adhoc.Info(after)))
        check('Angry Birds 2 %s: was %s; now ONE SHA-256 directory, all %d pages match, CDHash %s' % (rel, why[1] or 'usable-looking', len(after) // 4096, h),
              r and has and ok and r[0][1] == [h] and len(cds) == 1 and cds[0][1] == 2)
        if adhoc.Info(after).filetype == 2:
            check('   the executable keeps its entitlements byte for byte', blob_at(after, 5) == ents_before)
            # the same file again with the entitlement the kernel honours for exception ports added
            shutil.copy(src, dst)
            adhoc.resign(dst, os.path.join(tmp, 'ab2'), add_exec_entitlements=[KEY])
            with_key = read(dst)
            old = plistlib.loads(ents_before[8:])
            new = plistlib.loads(blob_at(with_key, 5)[8:])
            check('   with --add-exec-entitlement: its %d entitlements plus %s, DER present, all pages match' % (len(old), KEY),
                  new == dict(old, **{KEY: True}) and blob_at(with_key, 7) is not None and slice_state(with_key)[:2] == (True, True))
        elif ents_before:
            check('   the library\'s %d entitlements are left out' % r[0][2], blob_at(after, 5) is None and blob_at(after, 7) is None and r[0][2] > 0)
        hdr_end = 32 + adhoc.Info(before).sizeofcmds
        sig_old = adhoc.Info(before).sig_off
        diff = [k for k in range(sig_old) if before[k] != after[k]]
        check('   before the old signature only the load commands differ (%d bytes: the signature size, __LINKEDIT sizes)' % len(diff),
              all(k < hdr_end for k in diff) and len(diff) < 32)

    # why 24 files read "its code pages do not match its signature": FairPlay-decrypted App Store binaries. The directory is
    # version 0x20500 with its page hashes over the ENCRYPTED pages; the hashes of the plain pages are kept apart at
    # preEncryptOffset, and those match the file as it is. The bad pages are page 0 (cryptid zeroed) and the encrypted range.
    for rel in ('Frameworks/FBAEMKit.framework/FBAEMKit', 'Frameworks/Sentry.framework/Sentry'):
        src = os.path.join(ab2, rel)
        if not os.path.isfile(src):
            continue
        m = read(src)
        info = adhoc.Info(m)
        bl = adhoc.blobs(m, info)
        at = bl[0][0]
        v = struct.unpack_from('>IIIIIIIBBBB', m, at + 8)
        ver, hoff, ncode, limit = v[0], v[2], v[5], v[6]
        pre = struct.unpack_from('>I', m, at + 92)[0]
        o, enc = 32, None
        for _ in range(info.ncmds):
            c, sz = struct.unpack_from('<II', m, o)
            if c == 0x2c:
                enc = struct.unpack_from('<III', m, o + 8)
            o += sz
        cryptoff, cryptsize, cryptid = enc
        badp = [k for k in range(ncode) if hashlib.sha1(m[k * 4096:min((k + 1) * 4096, limit)]).digest() != m[at + hoff + 20 * k:at + hoff + 20 * (k + 1)]]
        prebad = [k for k in range(ncode) if hashlib.sha1(m[k * 4096:min((k + 1) * 4096, limit)]).digest() != m[at + pre + 20 * k:at + pre + 20 * (k + 1)]]
        inside = set(range(cryptoff // 4096, (cryptoff + cryptsize) // 4096))
        check('%s: CD %s, cryptid %d; %d bad pages are page 0 and pages of the old encrypted range; the pre-encrypt hashes match the file (%d mismatches)'
              % (rel, hex(ver), cryptid, len(badp), len(prebad)),
              ver == 0x20500 and cryptid == 0 and set(badp) <= inside | {0, 1} and not prebad and len(badp) > 0)

shutil.rmtree(tmp, ignore_errors=True)
print('failures:', bad)
sys.exit(1 if bad else 0)
