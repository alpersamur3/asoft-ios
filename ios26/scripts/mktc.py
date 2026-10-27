"""Build one trust cache out of others and CDHash lists.

    mktc.py [-2] OUT [IN ...]

IN is a trust cache (raw or IM4P-wrapped; version 1 with 22-byte entries or
version 2 with 24-byte entries) or a text file with one 40-hex-digit CDHash per
line. Entries are merged, deduplicated and sorted (the kernel binary-searches
them). Writes version 1, or version 2 with -2 (version 1 entries then get
constraint category 0).
"""
import struct, sys


def im4p_payload(buf):
    """Payload OCTET STRING of an IM4P (SEQUENCE { "IM4P", type, desc, payload, ... })."""
    def hdr(o):
        tag, ln = buf[o], buf[o + 1]
        o += 2
        if ln & 0x80:
            n = ln & 0x7f
            ln = int.from_bytes(buf[o:o + n], 'big')
            o += n
        return tag, ln, o
    tag, ln, o = hdr(0)
    assert tag == 0x30
    for _ in range(3):		# "IM4P", type, description
        _, l, o2 = hdr(o)
        o = o2 + l
    tag, ln, o = hdr(o)
    assert tag == 0x04
    return buf[o:o + ln]


def read_tc(buf):
    """{cdhash: (hashType, flags, constraintCategory)}"""
    if b'IM4P' in buf[:16]:
        buf = im4p_payload(buf)
    ver, = struct.unpack_from('<I', buf)
    n, = struct.unpack_from('<I', buf, 20)
    if ver == 1:
        size = 22
    elif ver == 2:
        size = 24
    else:
        raise SystemExit(f'trust cache version {ver} not supported')
    out = {}
    for i in range(n):
        e = buf[24 + size * i:24 + size * (i + 1)]
        out[e[:20]] = (e[20], e[21], e[22] if ver == 2 else 0)
    return out


def main():
    args = sys.argv[1:]
    ver = 2 if args and args[0] == '-2' else 1
    if ver == 2:
        args = args[1:]
    entries = {}
    for path in args[1:]:
        buf = open(path, 'rb').read()
        if buf[:1] in (b'\x30', b'\x01', b'\x02'):
            entries.update(read_tc(buf))
        else:
            for line in buf.decode().split():
                entries.setdefault(bytes.fromhex(line), (2, 0, 0))	# SHA-256 truncated, no flags
    out = struct.pack('<I', ver) + b'A' * 16 + struct.pack('<I', len(entries))
    for h in sorted(entries):
        t, f, c = entries[h]
        out += h + bytes([t, f]) + (bytes([c, 0]) if ver == 2 else b'')
    open(args[0], 'wb').write(out)
    print(f'{args[0]}: version {ver}, {len(entries)} entries')


if __name__ == '__main__':
    main()
