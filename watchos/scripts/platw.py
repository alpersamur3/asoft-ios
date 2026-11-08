"""Retarget thin or fat arm64 Mach-O files from iOS to watchOS in place, so watchOS's dyld
accepts them as main executables and dylibs: LC_VERSION_MIN_IPHONEOS (0x25) becomes
LC_VERSION_MIN_WATCHOS (0x30, same layout) and LC_BUILD_VERSION (0x32) platform 2 (iOS)
becomes 4 (watchOS). Run before ad-hoc signing (the CDHash covers the load commands).

    platw.py FILE...      prints one line per file it changed
"""
import struct, sys

LC_VERSION_MIN_IPHONEOS, LC_VERSION_MIN_WATCHOS, LC_BUILD_VERSION = 0x25, 0x30, 0x32


def patch_thin(b, off):
    magic, = struct.unpack_from('<I', b, off)
    if magic != 0xfeedfacf:
        return 0
    ncmds, = struct.unpack_from('<I', b, off + 16)
    p = off + 32
    n = 0
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', b, p)
        if cmd == LC_VERSION_MIN_IPHONEOS:
            struct.pack_into('<I', b, p, LC_VERSION_MIN_WATCHOS)
            n += 1
        elif cmd == LC_BUILD_VERSION:
            plat, = struct.unpack_from('<I', b, p + 8)
            if plat == 2:
                struct.pack_into('<I', b, p + 8, 4)
                n += 1
        p += size
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
            off, = struct.unpack_from('>I', b, 8 + i * 20 + 8)
            n += patch_thin(b, off)
    else:
        n = patch_thin(b, 0)
    if n:
        open(f, 'wb').write(b)
        print(f'{f}: {n} load command(s) -> watchOS')
