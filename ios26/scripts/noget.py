"""noget.py PATH ...: switch get-task-allow off in developer-signed Mach-O files, in place.

    noget.py app.app        every Mach-O under the folder (main binary, Frameworks, PlugIns)
    noget.py FILE           one Mach-O (thin or fat)

AMFI in the iOS 26 guest refuses a binary whose entitlements say get-task-allow = true while Developer Mode is
off ("Developer mode is disabled, get-task-allow is disallowed"). A .ipa signed with a development profile has it.
Per 64-bit slice: the XML entitlements (special slot 5) and the DER entitlements (slot 7) get the value false at the
same length, and every code directory (SHA-1 and SHA-256) hashes slots 5 and 7 again. Sizes and offsets do not
change, the code pages are not touched, so the signature stays as valid as it was; only the CDHash is new, and the
caller reads it with cdhash.py afterwards. A file without the entitlement, or with it false, is left alone.
Prints one line per changed file, "FAILED file: reason" for one it could not change; the exit code is 1 then.
"""
import hashlib
import os
import re
import struct
import sys

LC_CODE_SIGNATURE = 0x1d
CSMAGIC_EMBEDDED_SIGNATURE, CSMAGIC_CODEDIRECTORY = 0xfade0cc0, 0xfade0c02
CSMAGIC_ENTITLEMENTS, CSMAGIC_DER_ENTITLEMENTS = 0xfade7171, 0xfade7172
# DER: UTF8String "get-task-allow" followed by BOOLEAN
DER_KEY = b'\x0c\x0eget-task-allow'
XML_TRUE = re.compile(rb'(<key>get-task-allow</key>)(\s*)(<true\s*/>)')


def slices(b):
    """(offset, size) of every 64-bit Mach-O in a thin or fat file."""
    magic = struct.unpack_from('>I', b)[0]
    if magic in (0xcafebabe, 0xcafebabf):
        n = struct.unpack_from('>I', b, 4)[0]
        for i in range(n):
            if magic == 0xcafebabe:
                cpu, sub, off, size, _ = struct.unpack_from('>iiIII', b, 8 + 20 * i)
            else:
                cpu, sub, off, size, _, _ = struct.unpack_from('>iiQQII', b, 8 + 32 * i)
            if cpu & 0x1000000 and off + size <= len(b) and struct.unpack_from('<I', b, off)[0] == 0xfeedfacf:
                yield off, size
    elif struct.unpack_from('<I', b)[0] == 0xfeedfacf:
        yield 0, len(b)


def patch_slice(b, base):
    """Patch the slice at b[base:] in place. Returns True when something changed, False when there was
    nothing to do; raises ValueError for a get-task-allow it cannot switch off."""
    ncmds = struct.unpack_from('<I', b, base + 16)[0]
    o = base + 32
    sig = None
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', b, o)
        if cmd == LC_CODE_SIGNATURE:
            sig = struct.unpack_from('<II', b, o + 8)
        o += size
    if not sig or not sig[1]:
        return False
    sb = base + sig[0]
    smagic, _, count = struct.unpack_from('>III', b, sb)
    if smagic != CSMAGIC_EMBEDDED_SIGNATURE:
        return False
    # blob offsets are relative to the superblob; slot type -> (absolute offset, length, magic)
    blobs = {}
    for i in range(count):
        typ, off = struct.unpack_from('>II', b, sb + 12 + 8 * i)
        bm, bl = struct.unpack_from('>II', b, sb + off)
        blobs[typ] = (sb + off, bl, bm)

    changed = False
    if 5 in blobs and blobs[5][2] == CSMAGIC_ENTITLEMENTS:
        xo, xl, _ = blobs[5]
        xml = bytes(b[xo + 8:xo + xl])
        m = XML_TRUE.search(xml)
        if m:
            # "<true/>" is one byte shorter than "<false/>": the white space before it pays for it
            span = len(m.group(2)) + len(m.group(3))
            if span < 8:
                raise ValueError('get-task-allow is true in the XML entitlements with no space before the value, '
                                 'so false does not fit at the same length')
            new = m.group(1) + b'<false/>' + b' ' * (span - 8)
            xml = xml[:m.start()] + new + xml[m.end():]
            b[xo + 8:xo + xl] = xml
            changed = True
    if 7 in blobs and blobs[7][2] == CSMAGIC_DER_ENTITLEMENTS:
        do, dl, _ = blobs[7]
        der = bytes(b[do + 8:do + dl])
        true = DER_KEY + b'\x01\x01\xff'
        if true in der:
            b[do + 8:do + dl] = der.replace(true, DER_KEY + b'\x01\x01\x00')
            changed = True
    if not changed:
        return False

    # every code directory (the SHA-1 one and the SHA-256 one) hashes the entitlement blobs again
    for typ, (co, cl, cm) in blobs.items():
        if cm != CSMAGIC_CODEDIRECTORY:
            continue
        (version, flags, hash_off, ident_off, n_special, n_code, code_limit, hash_size,
         hash_type) = struct.unpack_from('>IIIIIIIBB', b, co + 8)
        h = {1: hashlib.sha1, 2: hashlib.sha256}.get(hash_type)
        if h is None:
            raise ValueError('a code directory with hash type %d' % hash_type)
        for slot in (5, 7):
            if slot in blobs and slot <= n_special:
                so, sl, _ = blobs[slot]
                at = co + hash_off - slot * hash_size
                b[at:at + hash_size] = h(bytes(b[so:so + sl])).digest()[:hash_size]
    return True


def patch_file(path):
    with open(path, 'rb') as f:
        head = f.read(4)
    if head not in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf', b'\xcf\xfa\xed\xfe'):
        return False
    with open(path, 'rb') as f:
        b = bytearray(f.read())
    changed = False
    for off, size in list(slices(b)):
        if patch_slice(b, off):
            changed = True
    if changed:
        with open(path, 'wb') as f:
            f.write(b)
    return changed


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    files = []
    for p in sys.argv[1:]:
        if os.path.isdir(p):
            for root, _, names in os.walk(p):
                files += [os.path.join(root, n) for n in sorted(names)]
        else:
            files.append(p)
    failed = 0
    for f in files:
        try:
            if patch_file(f):
                print('get-task-allow off: %s' % f)
        except (ValueError, struct.error, OSError) as e:
            print('FAILED %s: %s' % (f, e))
            failed += 1
    return 1 if failed else 0


sys.exit(main())
