"""Download one member of a remote zip (IPSW) with parallel HTTP range requests,
resumable, and check its CRC-32. Only stored (uncompressed) members, which the
disk images are.

    ipsw-get.py URL MEMBER OUTFILE [CONNECTIONS]

Chunks land at their own offsets in OUTFILE; OUTFILE.done lists finished chunks,
so a rerun only fetches what is missing.
"""
import concurrent.futures, http.client, os, struct, sys, threading, time, urllib.request, zlib

url, member, out = sys.argv[1:4]
conns = int(sys.argv[4]) if len(sys.argv) > 4 else 8
CHUNK = 32 << 20


def get(start, end):
    r = urllib.request.Request(url, headers={'Range': f'bytes={start}-{end}'})
    with urllib.request.urlopen(r, timeout=120) as resp:
        return resp.read()


def central_directory():
    size = int(urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=60).headers['Content-Length'])
    tail = get(size - 65536 - 22, size - 1)
    i = tail.rfind(b'PK\x06\x06')
    if i >= 0:
        cd_size, cd_off = struct.unpack_from('<QQ', tail, i + 40)
    else:
        i = tail.rfind(b'PK\x05\x06')
        cd_size, cd_off = struct.unpack_from('<II', tail, i + 12)
    return get(cd_off, cd_off + cd_size - 1)


def find(cd):
    o = 0
    while o < len(cd) and cd[o:o + 4] == b'PK\x01\x02':
        method, = struct.unpack_from('<H', cd, o + 10)
        crc, csize, usize = struct.unpack_from('<III', cd, o + 16)
        nlen, xlen, clen = struct.unpack_from('<HHH', cd, o + 28)
        lho, = struct.unpack_from('<I', cd, o + 42)
        name = cd[o + 46:o + 46 + nlen].decode()
        extra = cd[o + 46 + nlen:o + 46 + nlen + xlen]
        j = 0
        while j < len(extra):
            hid, hlen = struct.unpack_from('<HH', extra, j)
            if hid == 1:		# zip64: the fields that are 0xffffffff, in this order
                vals = list(struct.unpack_from(f'<{hlen // 8}Q', extra, j + 4))
                if usize == 0xffffffff:
                    usize = vals.pop(0)
                if csize == 0xffffffff:
                    csize = vals.pop(0)
                if lho == 0xffffffff:
                    lho = vals.pop(0)
            j += 4 + hlen
        if name == member:
            return method, crc, csize, usize, lho
        o += 46 + nlen + xlen + clen
    raise SystemExit(f'{member}: not in the zip')


method, crc, csize, usize, lho = find(central_directory())
lh = get(lho, lho + 29)
nlen, xlen = struct.unpack_from('<HH', lh, 26)
data = lho + 30 + nlen + xlen
if method == 8 and csize <= 256 << 20:	# small deflated member: in one go
    buf = zlib.decompressobj(-15).decompress(get(data, data + csize - 1))
    ok = len(buf) == usize and zlib.crc32(buf) == crc
    if ok:
        open(out, 'wb').write(buf)
    print(f'{member}: {usize} bytes, deflated {csize}: {"OK" if ok else "MISMATCH"}')
    sys.exit(0 if ok else 1)
if method != 0:
    raise SystemExit(f'{member}: compressed (method {method}), not supported')

done_path = out + '.done'
done = set()
if os.path.exists(done_path):
    done = {int(x) for x in open(done_path).read().split()}
if not os.path.exists(out) or os.path.getsize(out) != usize:
    with open(out, 'ab') as f:
        f.truncate(usize)
nchunks = (usize + CHUNK - 1) // CHUNK
todo = [i for i in range(nchunks) if i not in done]
print(f'{member}: {usize} bytes at {data}, {len(todo)}/{nchunks} chunks to fetch, {conns} connections', flush=True)

lock = threading.Lock()
t0, got = time.time(), 0


def fetch(i):
    global got
    start = i * CHUNK
    n = min(CHUNK, usize - start)
    for attempt in range(10):
        try:
            buf = get(data + start, data + start + n - 1)
            if len(buf) != n:
                raise OSError(f'short read {len(buf)}/{n}')
            break
        except (OSError, http.client.HTTPException) as e:
            print(f'chunk {i} retry {attempt}: {e}', flush=True)
            time.sleep(5 * (attempt + 1))
    else:
        raise SystemExit(f'chunk {i}: too many errors')
    with open(out, 'r+b') as f:
        f.seek(start)
        f.write(buf)
    with lock:
        with open(done_path, 'a') as d:
            d.write(f'{i}\n')
        got += n
        k = len(done) + got // CHUNK
        if k % 16 == 0:
            print(f'{k}/{nchunks} chunks, {got / (time.time() - t0) / 1e6:.1f} MB/s', flush=True)


with concurrent.futures.ThreadPoolExecutor(conns) as ex:
    list(ex.map(fetch, todo))

c = 0
with open(out, 'rb') as f:
    while True:
        b = f.read(64 << 20)
        if not b:
            break
        c = zlib.crc32(b, c)
print(f'crc {c:08x} expected {crc:08x}: {"OK" if c == crc else "MISMATCH"}')
if c == crc:
    os.remove(done_path)
sys.exit(0 if c == crc else 1)
