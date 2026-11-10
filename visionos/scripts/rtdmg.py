"""rtdmg.py: write the inner entry of the visionOS 27.2 (24N120) simulator runtime (the .dmg: a UDIF image whose LZFSE
chunks it holds; zero runs are not stored, so its chunk map at the end is needed to place them) to OUT as it is, for
apfs-fuse to read, streamed out of Apple's CDN without storing the archive: AEA plaintext (aearemote.Plain over INDEX,
which aearemote.py index made) -> outer Apple Archive (the "main" entry's DATC, a pbzx stream of 4 MB XZ chunks) ->
inner Apple Archive (AssetData/Restore/141-17665-166.dmg, DATC) -> OUT.

    python3 rtdmg.py INDEX OUT

A download that stopped goes on where it stopped: OUT.parts notes each finished part of OUT (whole pbzx chunks, about
a hundredth of the dmg: where the next chunk starts in the stream, OUT's length then, the part's SHA-256). A new run
checks every noted part against OUT, keeps OUT up to the last part that still matches (the first that does not is
said) and fetches the rest; without OUT.parts, or with one made for another INDEX, it starts from zero.

env EDGE=IP: connect to that CDN edge for updates.cdn-apple.com (in this process alone; TLS still checks the host
name). Some networks' DNS answer gives an edge at ~0.1 MB/s where Apple's 17.253.x.x edges give 4-7 MB/s
(measured 2026-11-08: 7.6 GB in 19 min through 17.253.15.135). Unset: the system's DNS.
"""
import ctypes, ctypes.util, hashlib, lzma, os, socket, struct, sys, time

EDGE = os.environ.get('EDGE', '')
if EDGE:
    _gai = socket.getaddrinfo
    def _pinned(host, *a, **k):
        return _gai(EDGE if host == 'updates.cdn-apple.com' else host, *a, **k)
    socket.getaddrinfo = _pinned
    print('CDN edge', EDGE, flush=True)

# aearemote.py beside this script
import importlib.util
spec = importlib.util.spec_from_file_location('aearemote', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'aearemote.py'))
aear = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aear)

if len(sys.argv) != 3:
    sys.exit(__doc__)
index, out_path = sys.argv[1], sys.argv[2]
P = aear.Plain(index, cache_mb=512)
P.ra = 48
P.pool = aear.concurrent.futures.ThreadPoolExecutor(16)

def plain_chunks(off, total, step=8 << 20):
    end = off + total
    while off < end:
        n = min(step, end - off)
        yield P.read(off, n)
        off += n


def aa_header(b):
    """An Apple Archive header at the start of b: (header size, {key: value}); blob fields map to their sizes."""
    assert b[:4] == b'AA01', b[:8]
    hsize = struct.unpack('<H', b[4:6])[0]
    f, i = {}, 6
    while i < hsize:
        key, t = b[i:i + 3].decode(), chr(b[i + 3]); i += 4
        if t in '1248':
            n = int(t); f[key] = int.from_bytes(b[i:i + n], 'little'); i += n
        elif t in 'ABC':
            n = {'A': 2, 'B': 4, 'C': 8}[t]; f[key] = ('blob', int.from_bytes(b[i:i + n], 'little')); i += n
        elif t == 'P':
            n = struct.unpack('<H', b[i:i + 2])[0]; f[key] = b[i + 2:i + 2 + n].decode(errors='replace'); i += 2 + n
        elif t == 'S':
            i += 8
        elif t == 'T':
            i += 12
        elif t == 'F':
            i += 16
        elif t == '*':
            f[key] = True
        else:
            raise ValueError(f'field {key}{t} at {i}')
    return hsize, f


# --- outer archive: walk the top-level entries to the one whose data is the pbzx stream
head = P.read(0, 1 << 16)
o = 0
while True:
    hs, f = aa_header(head[o:])
    blob = f['DAT'][1] if isinstance(f.get('DAT'), tuple) else 0
    if head[o + hs:o + hs + 4] == b'pbzx':
        pbzx_off, pbzx_len = o + hs, blob
        break
    o += hs + blob
print('pbzx at', pbzx_off, 'length', pbzx_len, flush=True)


def pbzx_inner(start=0):
    """The decompressed pbzx stream, chunk by chunk, each with where the next chunk starts in the stream; from the
    chunk at START (an earlier run's note), else from the stream's header."""
    buf = bytearray()
    src = plain_chunks(pbzx_off + start, pbzx_len - start)
    def need(n):
        while len(buf) < n:
            buf.extend(next(src))
    done = start
    if not start:
        need(12)
        assert buf[:4] == b'pbzx'
        del buf[:12]
        done = 12
    while done < pbzx_len:
        need(16)
        usize, csize = struct.unpack('>QQ', buf[:16])
        need(16 + csize)
        data = bytes(buf[16:16 + csize])
        del buf[:16 + csize]
        done += 16 + csize
        yield (lzma.decompress(data) if csize < usize else data), done


def lzfse_stream_len(b, i):
    """Length of the LZFSE stream at b[i:] (to the end of its bvx$ block) and its decoded size; None if b is short."""
    start, raw = i, 0
    while True:
        if len(b) < i + 4:
            return None
        m = bytes(b[i:i + 4])
        if m == b'bvx$':
            return i + 4 - start, raw
        if len(b) < i + 32:
            return None
        if m == b'bvx-':
            n = struct.unpack('<I', b[i + 4:i + 8])[0]; i += 8 + n; raw += n
        elif m == b'bvxn':  # LZVN block: magic, n_raw_bytes, n_payload_bytes, payload
            n_raw, n_pay = struct.unpack('<II', b[i + 4:i + 12]); i += 12 + n_pay; raw += n_raw
        elif m == b'bvx1':
            n_raw, n_pay = struct.unpack('<II', b[i + 4:i + 12])
            lit, lmd = struct.unpack('<II', b[i + 20:i + 28])
            i += 770 + lit + lmd; raw += n_raw  # v1 header: 7 u32 + i32 + 4 u16 + i32 + 3 u16 + 360 u16 = 770 bytes
        elif m == b'bvx2':  # LZFSE v2 block: packed header (its size in packed_fields[2]) + literal and LMD payloads
            n_raw = struct.unpack('<I', b[i + 4:i + 8])[0]
            f0, f1, f2 = struct.unpack('<QQQ', b[i + 8:i + 32])
            n_lit_pay = (f0 >> 20) & 0xFFFFF
            n_lmd_pay = (f1 >> 40) & 0xFFFFF
            hdr = f2 & 0xFFFFFFFF
            i += hdr + n_lit_pay + n_lmd_pay; raw += n_raw
        else:
            raise ValueError(f'bad LZFSE block magic {m!r} at {i} (stream at {start})')


parts_path = out_path + '.parts'
# (the parts belong to this INDEX's stream: another runtime or key makes other bytes)
index_sha = hashlib.sha256(open(index, 'rb').read()).hexdigest()


def finished_parts():
    """What an earlier run left that still holds: ((OUT's length, where the stream goes on, OUT.parts' length to
    keep, parts), the dmg's length) at the last noted part whose bytes in OUT have its SHA-256, else None."""
    try:
        with open(parts_path, 'rb') as f:
            lines = f.read().split(b'\n')
        size = os.path.getsize(out_path)
    except OSError:
        return None
    head = lines[0].split()
    if len(head) != 3 or head[0] != b'rtdmg-parts' or head[1] != index_sha.encode() or not head[2].isdigit():
        return None
    dat_len = int(head[2])
    keep = len(lines[0]) + 1
    good, end = None, 0
    with open(out_path, 'rb') as f:
        # (after the last newline: nothing, or a line a stop cut short, which notes no part)
        for n, line in enumerate(lines[1:-1], 1):
            w = line.split()
            if len(w) != 3 or not w[0].isdigit() or not w[1].isdigit():
                break
            start, end = end, int(w[1])
            if not start < end <= min(size, dat_len):
                print(f'part {n}: {out_path} has {size} bytes, not the {end} noted', flush=True)
                break
            h, left = hashlib.sha256(), end - start
            f.seek(start)
            while left:
                b = f.read(min(left, 8 << 20))
                if not b:
                    break
                h.update(b)
                left -= len(b)
            if left or h.hexdigest().encode() != w[2]:
                print(f'part {n} of {out_path} (bytes {start}-{end}) is not what was written: fetched again', flush=True)
                break
            keep += len(line) + 1
            good = (end, int(w[0]), keep, n)
    return (good, dat_len) if good else None


r = finished_parts()
t0 = time.time()
buf = bytearray()
if r:
    (written, start, keep, n), dat_len = r
    print(f'{out_path}: {n} finished parts checked, going on after {written >> 20} MiB of the dmg\'s '
          f'{dat_len >> 20}', flush=True)
    out = open(out_path, 'r+b')
    out.truncate(written)
    out.seek(written)
    parts = open(parts_path, 'r+b')
    parts.truncate(keep)
    parts.seek(keep)
    inner = pbzx_inner(start)
else:
    out = open(out_path, 'wb')
    parts = open(parts_path, 'wb')
    inner = pbzx_inner()
    for piece, start in inner:
        buf.extend(piece)
        if len(buf) >= 4096:
            break
    hs, f = aa_header(buf)
    print('inner entry', f.get('PAT'), f.get('DAT'), flush=True)
    if not str(f.get('PAT', '')).endswith('.dmg') or not isinstance(f.get('DAT'), tuple):
        sys.exit(f'the runtime\'s first inner entry is {f.get("PAT")!r}, not its .dmg (another runtime layout?)')
    dat_len = f['DAT'][1]
    del buf[:hs]
    parts.write(f'rtdmg-parts {index_sha} {dat_len}\n'.encode())
    written = 0
last = written
part, part_from = hashlib.sha256(), written
def emit(b):
    global written, last
    b = b[:dat_len - written]
    out.write(b)
    part.update(b)
    written += len(b)
    if written - last >= 512 << 20:
        last = written
        dt = time.time() - t0
        print(f'{time.strftime("%H:%M:%S")} dmg {written >> 20} MiB of {dat_len >> 20}, '
              f'{P.h.bytes / dt / 1e6:.1f} MB/s from CDN', flush=True)
# a part ends after a whole chunk (NEXT: where the next one starts); OUT's bytes go to the system before the line
# that notes them, and a line whose bytes did not make it is caught by its SHA-256
def mark(nxt):
    global part, part_from
    if written - part_from < max(dat_len // 100, 1) and written < dat_len:
        return
    out.flush()
    parts.write(f'{nxt} {written} {part.hexdigest()}\n'.encode())
    parts.flush()
    part, part_from = hashlib.sha256(), written
if buf:
    emit(bytes(buf))
    mark(start)
if written < dat_len:
    for piece, nxt in inner:
        emit(piece)
        mark(nxt)
        if written >= dat_len:
            break
out.close()
parts.close()
print('DONE dmg', written, 'of', dat_len, 'http', P.h.reqs, 'requests', P.h.bytes, 'bytes', f'{time.time() - t0:.0f} s', flush=True)
if written != dat_len:
    sys.exit(f'the stream ended after {written} of the dmg\'s {dat_len} bytes')
