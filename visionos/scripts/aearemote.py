"""Random access to the plaintext of an AEA member inside a remote IPSW, without downloading it.
Format: blacktop/ipsw pkg/aea (profile 1, HKDF-SHA256 + AES-CTR + HMAC): a chain of clusters, each with
a header of per-segment sizes; every segment is encrypted and compressed on its own, so one plaintext
byte costs one segment. The cluster walk is saved to an index file.

    aearemote.py index URL DATA_OFF KEYFILE HEADFILE INDEX      walk the clusters, write INDEX (json)
    aearemote.py read  INDEX PLAIN_OFF LEN OUT                  fetch and decrypt a range
    aearemote.py fuse  INDEX MOUNTDIR [CACHE_MB]                expose INDEX as MOUNTDIR/os.dmg (fusepy)
"""
import base64, collections, concurrent.futures, ctypes, ctypes.util, hashlib, hmac, json, os, struct, sys, threading, time
import http.client, urllib.parse
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

UA = {'User-Agent': 'python-aearemote'}


def hkdf(ikm, salt, info, n):
    prk = hmac.new(salt or b'\0' * 32, ikm, hashlib.sha256).digest()
    out, t, i = b'', b'', 1
    while len(out) < n:
        t = hmac.new(prk, t + info + bytes([i]), hashlib.sha256).digest()
        out += t
        i += 1
    return out[:n]


def ctr(data, key, iv):
    d = Cipher(algorithms.AES(key), modes.CTR(iv)).decryptor()
    return d.update(data) + d.finalize()


def material(ikm, info):
    b = hkdf(ikm, None, info, 80)
    return b[:32], b[32:64], b[64:80]		# mac, key, iv


class Http:
    def __init__(self, url):
        u = urllib.parse.urlsplit(url)
        self.host, self.path = u.netloc, u.path
        self.local = threading.local()
        self.bytes = 0
        self.reqs = 0

    def get(self, off, n):
        for attempt in range(12):
            c = getattr(self.local, 'c', None)
            try:
                if c is None:
                    c = self.local.c = http.client.HTTPSConnection(self.host, timeout=60)
                c.request('GET', self.path, headers={'Range': f'bytes={off}-{off + n - 1}', **UA})
                r = c.getresponse()
                b = r.read()
                if r.status != 206 or len(b) != n:
                    raise OSError(f'status {r.status}, {len(b)}/{n}')
                self.bytes += n
                self.reqs += 1
                return b
            except (OSError, http.client.HTTPException):
                if c is not None:
                    c.close()
                self.local.c = None
                time.sleep(1 + attempt)
        raise OSError('too many errors')


def do_index(url, data_off, keyfile, headfile, index):
    key = base64.b64decode(open(keyfile).read().strip().split(':')[-1])
    head = open(headfile, 'rb').read()
    magic, ps, alen = struct.unpack_from('<4sII', head, 0)
    assert magic == b'AEA1' and ps & 0xffffff == 1
    p = 12 + alen
    salt = head[p:p + 32]
    p += 32
    rh_mac, rh_data, first_cluster_mac = head[p:p + 32], head[p + 32:p + 80], head[p + 80:p + 112]
    p += 112
    main = hkdf(key, salt, b'AEA_AMK' + struct.pack('<I', ps), 32)
    _m, k, iv = material(main, b'AEA_RHEK')
    fsize, esize, segsz, nseg, comp, cks = struct.unpack_from('<QQIIBB', ctr(rh_data, k, iv), 0)
    cksz = {0: 0, 1: 8, 2: 32}[cks]
    print(f'plain {fsize}, encrypted {esize}, segment {segsz}, {nseg} per cluster, compression {chr(comp)!r}, checksum {cks}')
    h = Http(url)
    entry = cksz + 8
    hsize = entry * nseg + 32 + 32 * nseg
    clusters = []
    off, out, c = p, 0, 0
    mac = first_cluster_mac
    while out < fsize:
        ck = hkdf(main, None, b'AEA_CK' + struct.pack('<I', c), 32)
        m_mac, m_key, m_iv = material(ck, b'AEA_CHEK')
        ch = h.get(data_off + off, hsize)
        headers, macs = ch[:entry * nseg], ch[entry * nseg:]
        calc = hmac.new(m_mac, macs + headers + struct.pack('<Q', len(macs)), hashlib.sha256).digest()
        assert calc == mac, f'cluster {c} HMAC'
        mac = macs[:32]
        plain = ctr(headers, m_key, m_iv)
        segs = []
        inp = off + hsize
        first = out
        for i in range(nseg):
            d, s = struct.unpack_from('<II', plain, i * entry)
            if d == 0:
                continue
            segs.append(s)
            inp += s
            out += d
        clusters.append({'ck': ck.hex(), 'data': off + hsize, 'plain': first, 'segs': segs})
        off = inp
        c += 1
        if c % 16 == 0:
            print(f'cluster {c}: plain {out}, enc {off}', flush=True)
    print(f'{c} clusters, end {off}, http {h.reqs} requests {h.bytes} bytes')
    json.dump({'url': url, 'data_off': data_off, 'fsize': fsize, 'segsz': segsz, 'nseg': nseg, 'comp': comp,
               'clusters': clusters}, open(index, 'w'))


class Plain:
    """plaintext reader with an LRU of decoded segments"""

    def __init__(self, index, cache_mb=256):
        self.ix = json.load(open(index))
        self.h = Http(self.ix['url'])
        self.fsize, self.segsz = self.ix['fsize'], self.ix['segsz']
        self.perclust = self.ix['nseg'] * self.segsz
        self.cache = collections.OrderedDict()
        self.max = max(4, cache_mb * (1 << 20) // self.segsz)
        self.lock = threading.Lock()
        self.fetching = {}
        name = {ord('e'): 'lzfse', ord('-'): None, ord('b'): 'lzbitmap'}.get(self.ix['comp'])
        self.comp = name
        if name == 'lzfse':
            self.lz = ctypes.CDLL(ctypes.util.find_library('lzfse') or 'liblzfse.so.1')
            self.lz.lzfse_decode_buffer.restype = ctypes.c_size_t
            self.lz.lzfse_decode_buffer.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_void_p]
        elif name == 'lzbitmap':
            self.lz = ctypes.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'liblzbitmap.so'))
        self.stats = [0, 0]
        self.nseg_total = (self.fsize + self.segsz - 1) // self.segsz
        self.ra = 24
        self.queued = set()
        self.pool = concurrent.futures.ThreadPoolExecutor(8)

    def _seg(self, n):
        c = n // self.ix['nseg']
        i = n % self.ix['nseg']
        cl = self.ix['clusters'][c]
        off = cl['data'] + sum(cl['segs'][:i])
        csize = cl['segs'][i]
        raw = self.h.get(self.ix['data_off'] + off, csize)
        ck = bytes.fromhex(cl['ck'])
        _m, k, iv = material(ck, b'AEA_SK' + struct.pack('<I', i))
        d = ctr(raw, k, iv)
        dsize = min(self.segsz, self.fsize - n * self.segsz)
        if csize == dsize:
            return d
        out = ctypes.create_string_buffer(dsize + 1)
        if self.comp == 'lzfse':
            r = self.lz.lzfse_decode_buffer(out, dsize + 1, d, csize, None)
        elif self.comp == 'lzbitmap':
            r = self.lz.lzbitmap_decode(out, dsize + 1, d, csize)
        else:
            raise OSError(f'compression {self.ix["comp"]}')
        if r != dsize:
            raise OSError(f'segment {n}: decoded {r}, expected {dsize}')
        return out.raw[:dsize]

    def seg(self, n):
        while True:
            with self.lock:
                b = self.cache.get(n)
                if b is not None:
                    self.cache.move_to_end(n)
                    self.stats[0] += 1
                    return b
                ev = self.fetching.get(n)
                if ev is None:
                    ev = self.fetching[n] = threading.Event()
                    break
            ev.wait()
        try:
            b = self._seg(n)
            with self.lock:
                self.cache[n] = b
                self.stats[1] += 1
                while len(self.cache) > self.max:
                    self.cache.popitem(last=False)
            return b
        finally:
            with self.lock:
                self.fetching.pop(n, None)
            ev.set()

    def prefetch(self, s):
        """after two segments in a row, fetch the next ones in parallel (one line gives ~0.6 MB/s, 8 give 2-3)"""
        last = self.nseg_total - 1
        for n in range(s + 1, min(s + 1 + self.ra, last + 1)):
            with self.lock:
                if n in self.cache or n in self.fetching or n in self.queued:
                    continue
                self.queued.add(n)
            self.pool.submit(self._bg, n)

    def _bg(self, n):
        try:
            self.seg(n)
        except OSError as e:
            print('prefetch', n, e, flush=True)
        finally:
            with self.lock:
                self.queued.discard(n)

    def read(self, off, n):
        n = min(n, self.fsize - off)
        out = bytearray()
        while n > 0:
            s, o = divmod(off, self.segsz)
            with self.lock:
                seq = (s - 1) in self.cache
            if seq:
                self.prefetch(s)
            b = self.seg(s)
            k = min(n, len(b) - o)
            out += b[o:o + k]
            off += k
            n -= k
        return bytes(out)


def do_fuse(index, mnt, cache_mb):
    import errno, stat
    from fusepy import FUSE, FuseOSError, Operations
    P = Plain(index, cache_mb)
    NAME = '/os.dmg'
    t0 = time.time()

    class FS(Operations):
        def getattr(self, path, fh=None):
            if path == '/':
                return dict(st_mode=stat.S_IFDIR | 0o555, st_nlink=2, st_uid=0, st_gid=0, st_size=0, st_mtime=t0, st_atime=t0, st_ctime=t0)
            if path == NAME:
                return dict(st_mode=stat.S_IFREG | 0o444, st_nlink=1, st_uid=0, st_gid=0, st_size=P.fsize, st_mtime=t0, st_atime=t0, st_ctime=t0)
            raise FuseOSError(errno.ENOENT)

        def readdir(self, path, fh):
            return ['.', '..', NAME[1:]]

        def read(self, path, size, offset, fh):
            try:
                return P.read(offset, size)
            except OSError as e:
                print('read error', offset, size, e, flush=True)
                raise FuseOSError(errno.EIO)

    def stat_loop():
        last = 0
        while True:
            time.sleep(20)
            if P.h.bytes != last:
                last = P.h.bytes
                print(f'{time.strftime("%H:%M:%S")} http {P.h.reqs} req {P.h.bytes >> 20} MiB, seg hit {P.stats[0]} miss {P.stats[1]}', flush=True)
    threading.Thread(target=stat_loop, daemon=True).start()
    FUSE(FS(), mnt, foreground=True, ro=True, allow_other=True, nothreads=False)


if __name__ == '__main__':
    a = sys.argv[1]
    if a == 'index':
        do_index(sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6])
    elif a == 'read':
        p = Plain(sys.argv[2])
        b = p.read(int(sys.argv[3]), int(sys.argv[4]))
        open(sys.argv[5], 'wb').write(b)
        print(f'{len(b)} bytes, http {p.h.reqs} req {p.h.bytes} bytes, compression {p.comp}')
    elif a == 'fuse':
        do_fuse(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 256)
