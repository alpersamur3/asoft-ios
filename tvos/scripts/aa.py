"""Minimal Apple Archive (AA01 / YAA1) reader.

Header: magic(4) + u16 header size, then fields of key(3 chars) + subtype(1 char) + value.
Subtypes: '*' none, '1' '2' '4' '8' little-endian uint, 'P' u16 length + bytes,
'T' u64 sec + u32 nsec, 'S' u64 sec, 'A' 'B' 'C' blob of u16/u32/u64 size (the blobs follow the
header in field order), 'F' 4-byte, 'G' 20-byte, 'H' 32-byte, 'I' 48-byte, 'J' 64-byte digests.
"""
import struct

FIXED = {'1': 1, '2': 2, '4': 4, '8': 8, 'T': 12, 'S': 8, 'F': 4, 'G': 20, 'H': 32, 'I': 48, 'J': 64}
BLOB = {'A': 2, 'B': 4, 'C': 8}


class AAError(ValueError):
    pass


def parse_header(hdr):
    """hdr = header bytes after magic+size. Returns (fields dict, blobs list of (key, size))."""
    f, blobs, i, n = {}, [], 0, len(hdr)
    while i < n:
        if n - i < 4:
            raise AAError(f'truncated field key at {i}')
        key, st = hdr[i:i + 3].decode('latin1'), chr(hdr[i + 3])
        i += 4
        if st == '*':
            f[key] = True
        elif st in FIXED:
            w = FIXED[st]
            v = hdr[i:i + w]
            i += w
            if st in '1248':
                v = int.from_bytes(v, 'little')
            elif st == 'T':
                v = struct.unpack('<QI', v)
            elif st == 'S':
                v = (struct.unpack('<Q', v)[0], 0)
            f[key] = v
        elif st == 'P':
            (ln,) = struct.unpack_from('<H', hdr, i)
            f[key] = hdr[i + 2:i + 2 + ln].decode('utf-8', 'surrogateescape')
            i += 2 + ln
        elif st in BLOB:
            w = BLOB[st]
            sz = int.from_bytes(hdr[i:i + w], 'little')
            i += w
            blobs.append((key, sz))
        else:
            raise AAError(f'unknown field {key}{st}')
    if i != n:
        raise AAError('header overrun')
    return f, blobs


class Reader:
    """Sequential reader over a byte stream object with .read(n)."""

    def __init__(self, stream):
        self.s = stream
        self.pos = 0

    def read(self, n):
        out = bytearray()
        while len(out) < n:
            b = self.s.read(n - len(out))
            if not b:
                break
            out += b
        self.pos += len(out)
        return bytes(out)

    def entries(self):
        """Yield (fields, blobs, offset). The caller must consume each blob with read_blob/skip_blob in order."""
        while True:
            off = self.pos
            head = self.read(6)
            if not head:
                return
            if len(head) < 6:
                raise AAError(f'truncated entry at {off}')
            magic, hsize = head[:4], struct.unpack('<H', head[4:])[0]
            if magic not in (b'AA01', b'YAA1'):
                raise AAError(f'bad magic {magic!r} at {off}')
            hdr = self.read(hsize - 6)
            if len(hdr) != hsize - 6:
                raise AAError(f'truncated header at {off}')
            f, blobs = parse_header(hdr)
            yield f, blobs, off

    def copy_blob(self, size, out, chunk=8 << 20):
        left = size
        while left:
            b = self.read(min(chunk, left))
            if not b:
                raise AAError('truncated blob')
            if out is not None:
                out.write(b)
            left -= len(b)
