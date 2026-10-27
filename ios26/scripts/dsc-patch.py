"""Patch bytes in a dyld shared cache subcache and re-attest its code signature.

    dsc-patch.py DSC_DIR VADDR OLDHEX NEWHEX OUT_DIR

Finds the subcache file of DSC_DIR whose mappings hold VADDR, checks that the
bytes there are OLDHEX, writes a copy to OUT_DIR with NEWHEX in their place and
the changed page hashes recomputed in every CodeDirectory of the cache's code
signature. The CMS blob no longer matches; the new CDHash goes into a trust
cache, as for reattest.py. Prints "FILE OLD_CDHASH NEW_CDHASH".
"""
import hashlib, os, struct, sys

CSMAGIC_EMBEDDED_SIGNATURE, CSMAGIC_CODEDIRECTORY = 0xfade0cc0, 0xfade0c02
HASHES = {1: 'sha1', 2: 'sha256', 3: 'sha256', 4: 'sha384'}


def file_offset(buf, va):
    moff, mcount = struct.unpack_from('<II', buf, 0x10)
    for i in range(mcount):
        addr, size, foff = struct.unpack_from('<QQQ', buf, moff + 32 * i)
        if addr <= va < addr + size:
            return foff + va - addr
    return None


def code_directories(buf):
    sigoff, = struct.unpack_from('<Q', buf, 0x28)
    magic, _, count = struct.unpack_from('>III', buf, sigoff)
    assert magic == CSMAGIC_EMBEDDED_SIGNATURE, hex(magic)
    for i in range(count):
        _, off = struct.unpack_from('>II', buf, sigoff + 12 + 8 * i)
        if struct.unpack_from('>I', buf, sigoff + off)[0] == CSMAGIC_CODEDIRECTORY:
            yield sigoff + off


def cdhash(buf, cd):
    length, = struct.unpack_from('>I', buf, cd + 4)
    return buf[cd + 37], hashlib.new(HASHES[buf[cd + 37]], bytes(buf[cd:cd + length])).hexdigest()[:40]


def main():
    src, va, old, new, out = sys.argv[1], int(sys.argv[2], 0), bytes.fromhex(sys.argv[3]), bytes.fromhex(sys.argv[4]), sys.argv[5]
    assert len(old) == len(new)
    for name in sorted(os.listdir(src)):
        path = os.path.join(src, name)
        with open(path, 'rb') as f:
            head = f.read(0x4000)
        if not head.startswith(b'dyld_v1') or file_offset(head, va) is None:
            continue
        buf = bytearray(open(path, 'rb').read())
        fo = file_offset(buf, va)
        if buf[fo:fo + len(old)] != old:
            raise SystemExit(f'{name}+{fo:#x}: found {buf[fo:fo + len(old)].hex()}, expected {old.hex()}')
        orig = bytes(buf)
        buf[fo:fo + len(new)] = new
        before = dict(cdhash(buf, cd) for cd in code_directories(buf))
        for cd in code_directories(buf):
            hash_off, = struct.unpack_from('>I', buf, cd + 16)
            nslots, code_limit = struct.unpack_from('>II', buf, cd + 28)
            version, = struct.unpack_from('>I', buf, cd + 8)
            if version >= 0x20300 and code_limit == 0:
                code_limit, = struct.unpack_from('>Q', buf, cd + 56)
            hsize, htype, pshift = buf[cd + 36], buf[cd + 37], buf[cd + 39]
            ps = 1 << pshift
            first, last = fo // ps, (fo + len(new) - 1) // ps
            for i in range(first, last + 1):
                a, b = i * ps, min((i + 1) * ps, code_limit)
                assert hashlib.new(HASHES[htype], orig[a:b]).digest()[:hsize] == \
                    bytes(buf[cd + hash_off + i * hsize:cd + hash_off + (i + 1) * hsize]), 'stale page hash'
                buf[cd + hash_off + i * hsize:cd + hash_off + (i + 1) * hsize] = \
                    hashlib.new(HASHES[htype], bytes(buf[a:b])).digest()[:hsize]
        after = dict(cdhash(buf, cd) for cd in code_directories(buf))
        os.makedirs(out, exist_ok=True)
        open(os.path.join(out, name), 'wb').write(buf)
        best = 2 if 2 in after else max(after)
        print(name, before[best], after[best])
        return
    raise SystemExit(f'{va:#x} is in no subcache of {src}')


if __name__ == '__main__':
    main()
