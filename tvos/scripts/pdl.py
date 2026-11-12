"""Parallel range download from Apple's CDN, resumable, checked by its size and SHA-256.

usage: python -I pdl.py URL OUT SIZE SHA256 [IP[,IP...]|-] [WORKERS]
  IP     CDN edges to connect to (17.253.x.x where this network's DNS answer is slow); TLS still checks the
         host name. '-' or none: the host as DNS names it.
  The file grows as OUT.part (made at its full size), OUT.part.done lists the 32 MiB pieces that are in it,
so a run that stopped goes on with the rest. Once every piece is there its SHA-256 is checked: OUT only then.
A wrong hash removes nothing (exit 3): the caller decides (the size and pieces were right, so the source changed).
"""
import hashlib, http.client, os, socket, ssl, sys, threading, time

url, out, size, want = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4].lower()
ips = [i for i in (sys.argv[5].split(',') if len(sys.argv) > 5 else []) if i and i != '-']
workers = int(sys.argv[6]) if len(sys.argv) > 6 else 8
host = url.split('/')[2]
path = '/' + url.split('/', 3)[3]
CH = 32 << 20
part, state = out + '.part', out + '.part.done'
nch = (size + CH - 1) // CH
done = set()
if os.path.exists(part) and os.path.getsize(part) != size:
    # (another size: not this file's pieces)
    os.remove(part)
    if os.path.exists(state):
        os.remove(state)
if os.path.exists(state):
    done = {int(l) for l in open(state) if l.strip()}
if not os.path.exists(part):
    done = set()
    with open(part, 'wb') as f:
        f.truncate(size)
todo = [i for i in range(nch) if i not in done]
lock = threading.Lock()
got = [sum(min(CH, size - i * CH) for i in done)]
ctx = ssl.create_default_context()


class Conn(http.client.HTTPSConnection):
    def __init__(self, ip):
        super().__init__(host, 443, timeout=60, context=ctx)
        self.ip = ip

    def connect(self):
        s = socket.create_connection((self.ip or host, 443), 60)
        self.sock = ctx.wrap_socket(s, server_hostname=host)


def worker(k):
    ip = ips[k % len(ips)] if ips else None
    c = None
    while True:
        with lock:
            if not todo:
                return
            i = todo.pop(0)
        a, b = i * CH, min(size, (i + 1) * CH) - 1
        for tries in range(20):
            try:
                if c is None:
                    c = Conn(ip)
                c.request('GET', path, headers={'Host': host, 'Range': f'bytes={a}-{b}'})
                r = c.getresponse()
                if r.status != 206:
                    raise IOError(f'status {r.status}')
                data = r.read()
                if len(data) != b - a + 1:
                    raise IOError(f'short {len(data)}')
                with open(part, 'r+b') as f:
                    f.seek(a)
                    f.write(data)
                with lock:
                    done.add(i)
                    got[0] += len(data)
                    with open(state, 'a') as s:
                        s.write(f'{i}\n')
                break
            except Exception as e:
                print(f'piece {i} ip {ip or host} try {tries}: {e}', flush=True)
                try:
                    c.close()
                except Exception:
                    pass
                c = None
                if ips:
                    ip = ips[(ips.index(ip) + 1) % len(ips)]
                time.sleep(2)
        else:
            print(f'piece {i} failed 20 times', flush=True)
            os._exit(2)


t0, g0 = time.time(), got[0]
print(f'{len(todo)} of {nch} pieces to fetch ({(size - got[0]) / 1e9:.2f} GB), {workers} connections'
      f'{" to " + ",".join(ips) if ips else ""}', flush=True)
ts = [threading.Thread(target=worker, args=(k,), daemon=True) for k in range(workers)]
for t in ts:
    t.start()
while any(t.is_alive() for t in ts):
    time.sleep(15)
    el = time.time() - t0
    rate = (got[0] - g0) / el / 1e6 if el else 0
    left = (size - got[0]) / 1e6 / rate / 60 if rate else 0
    print(f'{got[0]/1e9:.2f}/{size/1e9:.2f} GB  {rate:.1f} MB/s  ~{left:.0f} min left', flush=True)
if len(done) != nch:
    print('incomplete', len(done), nch)
    sys.exit(2)
print('checking its SHA-256...', flush=True)
h = hashlib.sha256()
with open(part, 'rb') as f:
    while True:
        b = f.read(8 << 20)
        if not b:
            break
        h.update(b)
d = h.hexdigest()
print('sha256', d, 'OK' if d == want else 'MISMATCH, want ' + want, flush=True)
if d != want:
    sys.exit(3)
os.replace(part, out)
os.remove(state)
print('done', out, flush=True)
