"""CDHash (first 20 bytes of the CodeDirectory's SHA-256) of signed Mach-O files.

    cdhash.py FILE ...      prints "CDHASH FLAGS FILE" per slice, or "unsigned FILE"
"""
import hashlib, struct, sys

LC_CODE_SIGNATURE = 0x1d
CSMAGIC_EMBEDDED_SIGNATURE, CSMAGIC_CODEDIRECTORY = 0xfade0cc0, 0xfade0c02
CS_HASHTYPE_SHA256 = 2


def slices(buf):
    if len(buf) < 8:
        return
    magic, = struct.unpack_from('>I', buf)
    if magic in (0xcafebabe, 0xcafebabf):		# fat
        n, = struct.unpack_from('>I', buf, 4)
        for i in range(n):
            if magic == 0xcafebabe:
                cpu, sub, off, size, _ = struct.unpack_from('>iiIII', buf, 8 + 20 * i)
            else:
                cpu, sub, off, size, _, _ = struct.unpack_from('>iiQQII', buf, 8 + 32 * i)
            yield buf[off:off + size]
    elif struct.unpack_from('<I', buf)[0] == 0xfeedfacf:
        yield buf


def code_directories(m):
    ncmds, = struct.unpack_from('<I', m, 16)
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', m, off)
        if cmd == LC_CODE_SIGNATURE:
            dataoff, datasize = struct.unpack_from('<II', m, off + 8)
            sb = m[dataoff:dataoff + datasize]
            magic, length, count = struct.unpack_from('>III', sb)
            if magic != CSMAGIC_EMBEDDED_SIGNATURE:
                return
            for i in range(count):
                typ, boff = struct.unpack_from('>II', sb, 12 + 8 * i)
                cmagic, clen = struct.unpack_from('>II', sb, boff)
                if cmagic == CSMAGIC_CODEDIRECTORY:
                    flags, = struct.unpack_from('>I', sb, boff + 12)
                    hashtype = sb[boff + 37]
                    yield sb[boff:boff + clen], flags, hashtype
        off += size


def cdhashes(buf):
    for m in slices(buf):
        for cd, flags, hashtype in code_directories(m):
            if hashtype == CS_HASHTYPE_SHA256:
                yield hashlib.sha256(cd).hexdigest()[:40], flags


if __name__ == '__main__':
    for path in sys.argv[1:]:
        try:
            buf = open(path, 'rb').read()
        except OSError:
            continue
        found = False
        for h, flags in cdhashes(buf):
            print(h, hex(flags), path)
            found = True
        if not found:
            print('unsigned', path)
