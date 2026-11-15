"""Unpack an OS 27 full OTA's payloadv2 (pbzm/LZRAVEN chunks of one Apple Archive stream) into ROOT.

usage: python3 -I tvx.py OTA OUTER_JSON ROOT META_DIR
  OTA         decrypted OTA (outer AA01 archive)
  OUTER_JSON  index from index_outer.py (absolute offsets of AssetData/payloadv2/*)
  ROOT        empty directory on a POSIX filesystem (case-sensitive, symlinks, owners)
  META_DIR    where the report, BSD flags and xattrs go

Pass 1: payload.000..NNN in order, decoded by pbzm_dec, parsed as one stream: dirs, files (DAT), links.
Pass 2: fixup.manifest: final owner/mode for every path, symlinks, hard-link clusters (HLC, HLO>0 = link to
        the cluster's HLO 0 member). Then mtimes (files first, dirs last). Then counts are checked.
The decoder: $PBZM_DEC (Install-tvOS.ps1's lzraven step builds it in the Linux scratch), else pbzm_dec beside
this script. Ends with DONE (every path of the fixup manifest is there) or DONE-WITH-GAPS (META_DIR/report.json
names the missing ones).
"""
import base64
import collections
import gzip
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aa  # noqa: E402

PBZM = os.environ.get('PBZM_DEC') or os.path.join(HERE, 'pbzm_dec')
ota, outer_json, root, meta = sys.argv[1:5]
os.makedirs(meta, exist_ok=True)
files = {f['pat']: f for f in json.load(open(outer_json))['files']}
chunks = []
for n in range(1000):
    f = files.get(f'AssetData/payloadv2/payload.{n:03d}')
    if not f:
        break
    chunks.append((n, f['off'], f['size']))
log = open(os.path.join(meta, 'tvx.log'), 'a')


def say(*a):
    s = time.strftime('%H:%M:%S ') + ' '.join(str(x) for x in a)
    print(s, flush=True)
    log.write(s + '\n')
    log.flush()


class Chain:
    """Concatenate the decoded output of several pbzm containers (one pbzm_dec process at a time)."""

    def __init__(self, parts):
        self.parts = list(parts)
        self.p = None
        self.done = []

    def _next(self):
        if self.p:
            self.p.stdout.close()
            rc = self.p.wait()
            err = self.p.stderr.read().decode(errors='replace').strip()
            self.p.stderr.close()
            if rc != 0 or not err.startswith('OK '):
                raise SystemExit(f'pbzm_dec failed on part {self.cur}: rc={rc} {err}')
            self.done.append((self.cur, err))
            say(f'part {self.cur} {err}')
            self.p = None
        if not self.parts:
            return False
        self.cur, off, size = self.parts.pop(0)
        self.p = subprocess.Popen([PBZM, ota, str(off), str(size)], stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, bufsize=1 << 20)
        return True

    def read(self, n):
        while True:
            if self.p is None and not self._next():
                return b''
            b = self.p.stdout.read(n)
            if b:
                return b
            if not self._next():
                return b''


def safe(rel):
    """ROOT-relative path from an archive path; refuse absolute paths and '..'."""
    if rel.startswith('/') or any(p == '..' for p in rel.split('/')):
        raise SystemExit(f'unsafe path in archive: {rel!r}')
    return os.path.join(root, rel) if rel else root


def typ_of(f):
    return chr(f['TYP']) if isinstance(f.get('TYP'), int) else '?'


def drain(r, blobs, keep=()):
    """Consume an entry's blobs in order; return {key: bytes} for keys in keep (small blobs only)."""
    out = {}
    for k, sz in blobs:
        if k in keep:
            out[k] = r.read(sz)
        else:
            r.copy_blob(sz, None)
    return out


stats = collections.Counter()
mtimes = {}
flags = {}
xattrs = {}
written = set()

# ---------------- pass 1: payload chunks ----------------
say('pass 1:', len(chunks), 'chunks ->', root)
t0 = time.time()
ch = Chain(chunks)
r = aa.Reader(ch)
last = 0
for f, blobs, off in r.entries():
    t = typ_of(f)
    pat = f.get('PAT')
    if pat is None:
        stats[f'nopath-{t}'] += 1
        drain(r, blobs)
        continue
    dst = safe(pat)
    if f.get('FLG'):
        flags[pat] = [f.get('FLG'), f.get('AFT'), f.get('AFR')]
    if t == 'D':
        os.makedirs(dst, exist_ok=True)
        drain(r, blobs)
        stats['dir'] += 1
    elif t == 'F':
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.lexists(dst) and not os.path.isfile(dst):
            raise SystemExit(f'{pat}: exists and is not a file')
        got = False
        for k, sz in blobs:
            if k == 'DAT':
                with open(dst, 'wb') as out:
                    r.copy_blob(sz, out)
                stats['file_bytes'] += sz
                got = True
            elif k == 'XAT':
                xattrs[pat] = base64.b64encode(r.read(sz)).decode()
            else:
                r.copy_blob(sz, None)
        if not got:
            open(dst, 'wb').close()
            stats['file_nodat'] += 1
        if pat in written:
            stats['file_dup'] += 1
        written.add(pat)
        stats['file'] += 1
    elif t == 'L':
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.lexists(dst):
            os.unlink(dst)
        os.symlink(f['LNK'], dst)
        drain(r, blobs)
        stats['link'] += 1
    else:
        stats[f'other-{t}-{chr(f["YOP"]) if isinstance(f.get("YOP"), int) else ""}'] += 1
        drain(r, blobs)
        continue
    if 'MTM' in f:
        mtimes[pat] = f['MTM']
    if r.pos - last > 2 << 30:
        last = r.pos
        say(f'  {r.pos / 1e9:.1f} GB of stream, {stats["file"]} files, {stats["dir"]} dirs, '
            f'{(time.time() - t0) / 60:.1f} min')
ch.read(1)  # reap the last decoder
say('pass 1 done:', dict(stats), f'stream {r.pos} B, {(time.time() - t0) / 60:.1f} min')

# ---------------- pass 2: fixup.manifest ----------------
fx = files['AssetData/payloadv2/fixup.manifest']
fch = Chain([('fixup', fx['off'], fx['size'])])
fr = aa.Reader(fch)
clusters = collections.defaultdict(dict)
fixed = collections.Counter()
want_files = set()
want_dirs = set()
want_links = {}
modes = {}
for f, blobs, off in fr.entries():
    drain(fr, blobs)
    t = typ_of(f)
    pat = f.get('PAT')
    if pat is None:
        fixed[f'nopath-{t}'] += 1
        continue
    dst = safe(pat)
    if 'HLC' in f:
        clusters[f['HLC']][f.get('HLO', 0)] = pat
    if f.get('FLG'):
        flags.setdefault(pat, [f.get('FLG'), f.get('AFT'), f.get('AFR')])
    if t == 'L':
        want_links[pat] = f['LNK']
        if os.path.lexists(dst):
            if os.path.islink(dst) and os.readlink(dst) == f['LNK']:
                pass
            else:
                raise SystemExit(f'{pat}: wanted symlink -> {f["LNK"]}, found something else')
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            os.symlink(f['LNK'], dst)
            fixed['link_created'] += 1
        if 'UID' in f:
            os.lchown(dst, f['UID'], f.get('GID', 0))
        fixed['link'] += 1
        continue
    if t == 'D':
        want_dirs.add(pat)
    elif t == 'F' and f.get('HLO', 0) == 0:
        want_files.add(pat)
    if 'MOD' in f:
        modes[pat] = (f.get('UID', 0), f.get('GID', 0), f['MOD'])
    fixed[t] += 1
fch.read(1)
say('fixup records:', dict(fixed), 'clusters', len(clusters))

# hard links: HLO 0 is the member that carries the data
nlinks = 0
for hlc, mem in clusters.items():
    if 0 not in mem:
        raise SystemExit(f'cluster {hlc} has no HLO 0 member: {mem}')
    src = safe(mem[0])
    if not os.path.isfile(src):
        raise SystemExit(f'cluster {hlc}: primary {mem[0]} missing')
    for hlo, pat in mem.items():
        if hlo == 0:
            continue
        dst = safe(pat)
        if os.path.lexists(dst):
            os.unlink(dst)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        os.link(src, dst)
        nlinks += 1
say('hard links made:', nlinks)

# owners and modes (link members carry no MOD, so a cluster's inode gets its primary's values)
nmod = 0
for pat, (uid, gid, mod) in modes.items():
    p = safe(pat)
    if not os.path.lexists(p):
        continue
    os.chown(p, uid, gid)
    os.chmod(p, mod & 0o7777)
    nmod += 1
say('owner/mode set on', nmod)

# mtimes: files and links first, directories deepest-first last
def realdir(p):
    return os.path.isdir(p) and not os.path.islink(p)


for pat, (s, ns) in mtimes.items():
    p = safe(pat)
    if os.path.lexists(p) and not realdir(p):
        os.utime(p, ns=(s * 10**9 + ns, s * 10**9 + ns), follow_symlinks=False)
for pat in sorted((p for p in mtimes if realdir(safe(p))), key=lambda p: -p.count('/')):
    s, ns = mtimes[pat]
    os.utime(safe(pat), ns=(s * 10**9 + ns, s * 10**9 + ns))

# ---------------- checks ----------------
missing_files = sorted(p for p in want_files if not os.path.isfile(safe(p)))
missing_dirs = sorted(p for p in want_dirs if not os.path.isdir(safe(p)))
extra = sorted(written - want_files - {m for c in clusters.values() for m in c.values()})
report = {
    'pass1': dict(stats), 'fixup': dict(fixed), 'clusters': len(clusters), 'hardlinks': nlinks,
    'symlinks': len(want_links), 'want_files': len(want_files), 'want_dirs': len(want_dirs),
    'missing_files': missing_files[:200], 'n_missing_files': len(missing_files),
    'missing_dirs': missing_dirs[:200], 'n_missing_dirs': len(missing_dirs),
    'files_not_in_fixup': extra[:200], 'n_files_not_in_fixup': len(extra),
    'decoder': ch.done,
}
json.dump(report, open(os.path.join(meta, 'report.json'), 'w'), indent=1)
with gzip.open(os.path.join(meta, 'bsd-flags.json.gz'), 'wt') as g:
    json.dump(flags, g)
with gzip.open(os.path.join(meta, 'xattrs.json.gz'), 'wt') as g:
    json.dump(xattrs, g)
say('report:', {k: v for k, v in report.items() if not isinstance(v, list)})
say('DONE' if not missing_files and not missing_dirs else 'DONE-WITH-GAPS')
