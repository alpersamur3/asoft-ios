"""Retarget thin arm64 Mach-O files from iOS to visionOS (platform 11) in place, before ad-hoc signing:
LC_VERSION_MIN_IPHONEOS (0x25, 16 bytes; visionOS has no VERSION_MIN command) becomes LC_BUILD_VERSION
(0x32, 24 bytes, platform 11, minos 1.0, sdk 27.2, no tools); the later load commands move up 8 bytes into
the header padding. LC_BUILD_VERSION platform 2 becomes 11. darwin-vm's sysroot has >= 14 KiB of padding.

    platx.py FILE...      prints one line per file it changed
"""
import struct, sys

PLAT, MINOS, SDK = 11, 0x00010000, 0x001b0200


def patch_thin(b, off):
    magic, = struct.unpack_from('<I', b, off)
    if magic != 0xfeedfacf:
        return 0
    ncmds, sc = struct.unpack_from('<II', b, off + 16)
    p = off + 32
    end = p + sc
    first = None
    n = 0
    q = p
    cmds = []
    for _ in range(ncmds):
        c, s = struct.unpack_from('<II', b, q)
        cmds.append((q, c, s))
        if c == 0x19:
            ns, = struct.unpack_from('<I', b, q + 64)
            for i in range(ns):
                so, = struct.unpack_from('<I', b, q + 72 + i * 80 + 48)
                if so and (first is None or so < first):
                    first = so
        q += s
    for q, c, s in cmds:
        if c == 0x32:
            plat, = struct.unpack_from('<I', b, q + 8)
            if plat == 2:
                struct.pack_into('<I', b, q + 8, PLAT)
                n += 1
    for q, c, s in cmds:
        if c == 0x25:
            assert s == 16
            if first is not None and off + first < end + 8:
                raise SystemExit('no header padding')
            tail = bytes(b[q + 16:end])
            b[q:q + 24] = struct.pack('<IIIIII', 0x32, 24, PLAT, MINOS, SDK, 0)
            b[q + 24:q + 24 + len(tail)] = tail
            struct.pack_into('<I', b, off + 20, sc + 8)
            n += 1
            break
    return n


for f in sys.argv[1:]:
    b = bytearray(open(f, 'rb').read())
    if len(b) < 32:
        continue
    magic, = struct.unpack_from('>I', b, 0)
    n = 0
    if magic == 0xcafebabe:
        nfat, = struct.unpack_from('>I', b, 4)
        for i in range(nfat):
            o, = struct.unpack_from('>I', b, 8 + i * 20 + 8)
            n += patch_thin(b, o)
    else:
        n = patch_thin(b, 0)
    if n:
        open(f, 'wb').write(b)
        print(f'{f}: {n} load command(s) -> visionOS')
