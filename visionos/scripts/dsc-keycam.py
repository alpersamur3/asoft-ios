"""visionOS: the simulator's keyboard camera moves the head only while one key is held.

    dsc-keycam.py DSC_DIR OUT_DIR [--usage 0x6c] [--dry]

RealitySimulation (backboardd) moves and turns the head with W/A/S/D, R/F, Q/E and Shift whatever has the
keyboard: typing a text with those letters, or a capital, walked the head away. Its keyboard camera
(RSKeyboardTransform) is a list of key transforms; every one that moves or turns the head goes through one
method of their common class:

    if ([self isKeyDown] && [[self keyboard] enabled]) { ease; [self displaceTransform:magnitude:]; }

(`enabled` starts true and only Ctrl+K flips it: the toggle sits behind a Control modifier, so it cannot be
driven from outside without holding Control over the user's typing.) Patched, six words in one subcache:

    if ([self isKeyDown] && [[self keyboard] isKeyDown:USAGE]) { ... }

with the instructions the class's own -isKeyDown uses (the weak `keyboard` at self+0x10, the isKeyDown: stub).
USAGE is 0x6C by default, which QEMU's usb-kbd sends for Linux KEY_F13: usb-touchscreen walk-hold-key=183
holds it while walk mode is on. Outside walk mode the keyboard only writes.

The two sites are found by their instructions (branch targets masked); each must match exactly once in the
cache. The patched subcache goes to OUT_DIR with the touched page hashes recomputed in every CodeDirectory;
prints "FILE OLD_CDHASH NEW_CDHASH" as dsc-patch.py does (the new CDHash goes into the trust cache). A cache
that already has the patch prints "FILE CDHASH CDHASH already" and writes nothing.
"""
import hashlib
import importlib.util
import os
import struct
import sys

spec = importlib.util.spec_from_file_location('dscpatch', os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                                        'dsc-patch.py'))
dp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dp)

BL = (0x94000000, 0xfc000000)          # bl <anywhere>


def exact(w):
    return (w, 0xffffffff)


# The gate in the key transforms' -modifyTransform:targetTime:, from the bl of its isKeyDown
GATE = [
    BL,                 # 00 bl   isKeyDown
    exact(0x34000420),  # 04 cbz  w0, +0x84
    exact(0xaa1303e0),  # 08 mov  x0, x19                         -> add  x0, x19, #0x10
    BL,                 # 0c bl   keyboard                        -> bl   objc_loadWeakRetained
    exact(0xaa1d03fd),  # 10 mov  x29, x29                        -> mov  x20, x0
    BL,                 # 14 bl   objc_retainAutoreleasedReturnValue -> movz w2, #USAGE
    exact(0xaa0003f4),  # 18 mov  x20, x0                         -> mov  x0, x20
    BL,                 # 1c bl   enabled                         -> bl   isKeyDown:
    exact(0xaa0003f5),  # 20 mov  x21, x0
    BL,                 # 24 bl   objc_release_x20
    exact(0x34000315),  # 28 cbz  w21, +0x60
    exact(0xfd400e60),  # 2c ldr  d0, [x19, #0x18]
    exact(0x1e602008),  # 30 fcmp d0, #0.0
]
# The class's -isKeyDown, from its mov x19, x0: where the two calls the patch needs go to
ISKD = [
    exact(0xaa0003f3),  # 00 mov  x19, x0
    exact(0x91004000),  # 04 add  x0, x0, #0x10
    BL,                 # 08 bl   objc_loadWeakRetained
    exact(0xaa0003f4),  # 0c mov  x20, x0
    exact(0xf9400662),  # 10 ldr  x2, [x19, #8]
    BL,                 # 14 bl   isKeyDown:
    exact(0xaa0003f3),  # 18 mov  x19, x0
    BL,                 # 1c bl   objc_release_x20
]
ADD_X0_X19_16, MOV_X20_X0, MOV_X0_X20 = 0x91004260, 0xaa0003f4, 0xaa1403e0


def movz_w2(imm):
    return 0x52800002 | (imm << 5)


def word(buf, off):
    return struct.unpack_from('<I', buf, off)[0]


def find(buf, site, replaced=()):
    """Offsets where @site matches; the words at the offsets in @replaced may be anything."""
    anchor = next(i for i, (w, m) in enumerate(site) if m == 0xffffffff and 4 * i not in replaced)
    first, hits = struct.pack('<I', site[anchor][0]), []
    i = buf.find(first)
    while i >= 0:
        off = i - 4 * anchor
        if off >= 0 and off % 4 == 0 and off + 4 * len(site) <= len(buf) and all(
                4 * k in replaced or not (word(buf, off + 4 * k) ^ w) & m for k, (w, m) in enumerate(site)):
            hits.append(off)
        i = buf.find(first, i + 1)
    return hits


def retarget(buf, src, dst):
    """The bl at @dst that calls what the bl at @src calls."""
    imm = word(buf, src) & 0x03ffffff
    if imm & 0x02000000:
        imm -= 0x04000000
    imm += (src - dst) // 4
    assert -0x02000000 <= imm < 0x02000000
    return 0x94000000 | (imm & 0x03ffffff)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    src, out = args[0], args[1]
    dry = '--dry' in sys.argv
    usage = int(sys.argv[sys.argv.index('--usage') + 1], 0) if '--usage' in sys.argv else 0x6c
    assert 0 < usage < 0x100
    new_words = {0x08: ADD_X0_X19_16, 0x10: MOV_X20_X0, 0x14: movz_w2(usage), 0x18: MOV_X0_X20}
    found = []
    for name in sorted(os.listdir(src)):
        path = os.path.join(src, name)
        with open(path, 'rb') as f:
            if f.read(7) != b'dyld_v1':
                continue
            f.seek(0)
            buf = f.read()
        for off in find(buf, GATE):
            found.append((name, path, off, False))
        for off in find(buf, GATE, replaced=(0x08, 0x10, 0x14, 0x18)):
            if all(word(buf, off + o) == w for o, w in new_words.items()):
                found.append((name, path, off, True))
    if len(found) != 1:
        raise SystemExit(f'keycam: {len(found)} matches of the key transforms\' gate, expected 1 (another visionOS '
                         'build?): ' + ', '.join(f'{n}+{o:#x}{" patched" if p else ""}' for n, _, o, p in found))
    name, path, off, patched = found[0]
    buf = bytearray(open(path, 'rb').read())
    orig = bytes(buf)
    cds = list(dp.code_directories(buf))
    before = dict(dp.cdhash(buf, cd) for cd in cds)
    best = 2 if 2 in before else max(before)
    if patched:
        print(name, before[best], before[best], 'already')
        return
    iskd = find(buf, ISKD)
    if len(iskd) != 1:
        raise SystemExit(f'keycam: {len(iskd)} matches of the key transforms\' isKeyDown in {name}, expected 1')
    edits = {off + o: w for o, w in new_words.items()}
    edits[off + 0x0c] = retarget(buf, iskd[0] + 0x08, off + 0x0c)
    edits[off + 0x1c] = retarget(buf, iskd[0] + 0x14, off + 0x1c)
    for o, w in edits.items():
        struct.pack_into('<I', buf, o, w)
    for cd in cds:
        hash_off, = struct.unpack_from('>I', buf, cd + 16)
        nslots, code_limit = struct.unpack_from('>II', buf, cd + 28)
        version, = struct.unpack_from('>I', buf, cd + 8)
        if version >= 0x20300 and code_limit == 0:
            code_limit, = struct.unpack_from('>Q', buf, cd + 56)
        hsize, htype, pshift = buf[cd + 36], buf[cd + 37], buf[cd + 39]
        ps = 1 << pshift
        for page in sorted({o // ps for o in edits}):
            a, b = page * ps, min((page + 1) * ps, code_limit)
            slot = slice(cd + hash_off + page * hsize, cd + hash_off + (page + 1) * hsize)
            assert hashlib.new(dp.HASHES[htype], orig[a:b]).digest()[:hsize] == bytes(buf[slot]), 'stale page hash'
            buf[slot] = hashlib.new(dp.HASHES[htype], bytes(buf[a:b])).digest()[:hsize]
    after = dict(dp.cdhash(buf, cd) for cd in cds)
    if not dry:
        os.makedirs(out, exist_ok=True)
        open(os.path.join(out, name), 'wb').write(buf)
    print(name, before[best], after[best])
    print(f'keycam: gate at {name}+{off:#x}, isKeyDown at +{iskd[0]:#x} -> usage {usage:#x}{" (dry)" if dry else ""}: '
          + ' '.join(f'{o - off:02x}:{w:08x}' for o, w in sorted(edits.items())), file=sys.stderr)


if __name__ == '__main__':
    main()
