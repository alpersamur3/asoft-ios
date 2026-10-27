"""Re-attest a patched, signed Mach-O: recompute the page hashes that changed in
every CodeDirectory of its embedded signature, keeping everything else
(identifier, entitlements, flags). The CMS signature no longer matches; the
new CDHash goes into a trust cache instead, as for any platform binary.

    reattest.py ORIGINAL PATCHED      (PATCHED is updated in place)

Prints "OLD_CDHASH NEW_CDHASH PATCHED" (40 hex digits, the SHA-256 CodeDirectory
as in a version 2 trust cache) and how many pages changed. Thin Mach-O only.
"""
import hashlib, struct, sys

LC_CODE_SIGNATURE = 0x1d
CSMAGIC_EMBEDDED_SIGNATURE, CSMAGIC_CODEDIRECTORY = 0xfade0cc0, 0xfade0c02


def signature(buf):
    magic, _, _, _, ncmds, _ = struct.unpack_from('<IiiIII', buf)
    if magic != 0xfeedfacf:
        raise SystemExit('not a thin 64-bit Mach-O')
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', buf, off)
        if cmd == LC_CODE_SIGNATURE:
            return struct.unpack_from('<II', buf, off + 8)
        off += size
    raise SystemExit('not signed')


def code_directories(buf, sigoff):
    magic, _, count = struct.unpack_from('>III', buf, sigoff)
    assert magic == CSMAGIC_EMBEDDED_SIGNATURE
    for i in range(count):
        _, off = struct.unpack_from('>II', buf, sigoff + 12 + 8 * i)
        if struct.unpack_from('>I', buf, sigoff + off)[0] == CSMAGIC_CODEDIRECTORY:
            yield sigoff + off


def cdhash(buf, cd):
    length, = struct.unpack_from('>I', buf, cd + 4)
    htype = buf[cd + 37]
    return htype, hashlib.new({1: 'sha1', 2: 'sha256', 3: 'sha256', 4: 'sha384'}[htype],
                              bytes(buf[cd:cd + length])).hexdigest()[:40]


def main():
    orig = open(sys.argv[1], 'rb').read()
    buf = bytearray(open(sys.argv[2], 'rb').read())
    sigoff, _ = signature(buf)
    if len(orig) != len(buf) or orig[sigoff:] != buf[sigoff:]:
        raise SystemExit('size or signature differs: patch code only, in place')
    old = {h: v for h, v in (cdhash(buf, cd) for cd in code_directories(buf, sigoff))}
    changed = set()
    for cd in code_directories(buf, sigoff):
        hash_off, = struct.unpack_from('>I', buf, cd + 16)
        nslots, code_limit = struct.unpack_from('>II', buf, cd + 28)
        hsize, htype, _, pshift = buf[cd + 36], buf[cd + 37], buf[cd + 38], buf[cd + 39]
        ps = 1 << pshift
        for i in range(nslots):
            a, b = i * ps, min((i + 1) * ps, code_limit)
            if orig[a:b] != buf[a:b]:
                changed.add(a)
                h = hashlib.new({1: 'sha1', 2: 'sha256', 3: 'sha256', 4: 'sha384'}[htype],
                                bytes(buf[a:b])).digest()[:hsize]
                buf[cd + hash_off + i * hsize:cd + hash_off + (i + 1) * hsize] = h
    new = {h: v for h, v in (cdhash(buf, cd) for cd in code_directories(buf, sigoff))}
    open(sys.argv[2], 'wb').write(buf)
    best = 2 if 2 in new else max(new)
    print(old[best], new[best], sys.argv[2])
    print(f'{len(changed)} changed region(s) re-hashed', file=sys.stderr)


if __name__ == '__main__':
    main()
