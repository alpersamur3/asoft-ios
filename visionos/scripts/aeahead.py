"""Save the first bytes of a stored member of a remote zip, so `ipsw fw aea -k` can read its auth data.
    aeahead.py URL MEMBER OUT [BYTES]     prints the member's data offset and size
"""
import struct, sys, urllib.request
url, member, out = sys.argv[1:4]
n = int(sys.argv[4]) if len(sys.argv) > 4 else 1 << 20
UA = {'User-Agent': 'python-aeahead'}


def get(s, e):
    r = urllib.request.Request(url, headers={'Range': f'bytes={s}-{e}', **UA})
    with urllib.request.urlopen(r, timeout=120) as resp:
        return resp.read()


size = int(urllib.request.urlopen(urllib.request.Request(url, method='HEAD', headers=UA), timeout=60).headers['Content-Length'])
tail = get(size - 65536 - 22, size - 1)
i = tail.rfind(b'PK\x06\x06')
if i >= 0:
    cd_size, cd_off = struct.unpack_from('<QQ', tail, i + 40)
else:
    i = tail.rfind(b'PK\x05\x06')
    cd_size, cd_off = struct.unpack_from('<II', tail, i + 12)
cd = get(cd_off, cd_off + cd_size - 1)
o = 0
while o < len(cd) and cd[o:o + 4] == b'PK\x01\x02':
    method, = struct.unpack_from('<H', cd, o + 10)
    _crc, csize, usize = struct.unpack_from('<III', cd, o + 16)
    nlen, xlen, clen = struct.unpack_from('<HHH', cd, o + 28)
    lho, = struct.unpack_from('<I', cd, o + 42)
    name = cd[o + 46:o + 46 + nlen].decode()
    extra = cd[o + 46 + nlen:o + 46 + nlen + xlen]
    j = 0
    while j < len(extra):
        hid, hlen = struct.unpack_from('<HH', extra, j)
        if hid == 1:
            vals = list(struct.unpack_from(f'<{hlen // 8}Q', extra, j + 4))
            if usize == 0xffffffff:
                usize = vals.pop(0)
            if csize == 0xffffffff:
                csize = vals.pop(0)
            if lho == 0xffffffff:
                lho = vals.pop(0)
        j += 4 + hlen
    if name == member:
        break
    o += 46 + nlen + xlen + clen
else:
    raise SystemExit('member not found')
assert method == 0, method
lh = get(lho, lho + 29)
a, b = struct.unpack_from('<HH', lh, 26)
data = lho + 30 + a + b
open(out, 'wb').write(get(data, data + n - 1))
print(f'{member}: data at {data}, {usize} bytes, method {method}')
