"""Verify an extracted root against Apple's code signatures and the OS trust cache.

usage: python3 -I vsig.py ROOT TRUSTCACHE MKTC_DIR OUT.json
For every Mach-O (thin/fat) and dyld shared cache file under ROOT (hard links counted once):
  - every code page hash in its CodeDirectories must match the file bytes;
  - the CDHash of its SHA-256 (else best) CodeDirectory is looked up in the trust cache.
"""
import hashlib
import json
import os
import struct
import sys
import time

root, tcpath, mktc_dir, outp = sys.argv[1:5]
sys.path.insert(0, mktc_dir)
from mktc import read_tc  # noqa: E402

tc = read_tc(open(tcpath, 'rb').read())
HASH = {1: hashlib.sha1, 2: hashlib.sha256, 3: hashlib.sha256, 4: hashlib.sha384}
# hashType 3 = SHA-256 truncated to 20 bytes in the CD slots


def cds_of(blob):
    if len(blob) < 12:
        return []
    magic, length, count = struct.unpack_from('>III', blob)
    if magic == 0xfade0c02:
        return [blob[:length]]
    if magic != 0xfade0cc0:
        return []
    out = []
    for i in range(count):
        typ, off = struct.unpack_from('>II', blob, 12 + 8 * i)
        if typ == 0 or 0x1000 <= typ < 0x1005:
            m, ln = struct.unpack_from('>II', blob, off)
            if m == 0xfade0c02:
                out.append(blob[off:off + ln])
    return out


def check_cd(fh, base, cd):
    """Return (cdhash, hashType, pages_ok, npages, why)."""
    (magic, length, version, flags, hashOffset, identOffset, nSpecial, nCode, codeLimit, hashSize, hashType,
     platform, pageSize) = struct.unpack_from('>IIIIIIIIIBBBB', cd)
    limit = codeLimit
    if version >= 0x20300 and len(cd) >= 0x40:
        cl64, = struct.unpack_from('>Q', cd, 0x38)
        if cl64:
            limit = cl64
    h = HASH.get(hashType)
    if not h:
        return None, hashType, False, nCode, f'hash type {hashType}'
    psz = 1 << pageSize if pageSize else limit
    for i in range(nCode):
        fh.seek(base + i * psz)
        data = fh.read(min(psz, limit - i * psz))
        want = cd[hashOffset + i * hashSize:hashOffset + (i + 1) * hashSize]
        if h(data).digest()[:hashSize] != want:
            return None, hashType, False, nCode, f'page {i} mismatch'
    return h(cd).digest()[:20], hashType, True, nCode, ''


def macho_slices(fh, size):
    fh.seek(0)
    head = fh.read(8)
    if len(head) < 8:
        return None
    m_be = struct.unpack('>I', head[:4])[0]
    m_le = struct.unpack('<I', head[:4])[0]
    if m_be in (0xcafebabe, 0xcafebabf):
        n = struct.unpack('>I', head[4:8])[0]
        if n == 0 or n > 30:
            return None  # Java class files share 0xcafebabe
        out = []
        fh.seek(8)
        for _ in range(n):
            if m_be == 0xcafebabe:
                ct, st, off, sz, al = struct.unpack('>iiIII', fh.read(20))
            else:
                ct, st, off, sz, al, _r = struct.unpack('>iiQQII', fh.read(32))
            out.append((off, sz))
        return out
    if m_le in (0xfeedfacf, 0xfeedface):
        return [(0, size)]
    return None


def sig_of_slice(fh, off):
    fh.seek(off)
    hdr = fh.read(32)
    magic, ct, st, ft, ncmds, sizeofcmds = struct.unpack_from('<IiiIII', hdr)
    hsz = 32 if magic == 0xfeedfacf else 28
    fh.seek(off + hsz)
    cmds = fh.read(sizeofcmds)
    p = 0
    if len(cmds) < sizeofcmds:
        raise ValueError(f'load commands truncated ({len(cmds)} of {sizeofcmds})')
    for _ in range(ncmds):
        if p + 8 > len(cmds):
            raise ValueError('load command overrun')
        cmd, csz = struct.unpack_from('<II', cmds, p)
        if csz < 8:
            raise ValueError('bad cmdsize')
        if cmd == 0x1d:
            doff, dsz = struct.unpack_from('<II', cmds, p + 8)
            fh.seek(off + doff)
            return fh.read(dsz)
        p += csz
    return None


def dsc_sig(fh):
    fh.seek(0)
    h = fh.read(0x38)
    if not h.startswith(b'dyld_v1'):
        return None
    cso, css = struct.unpack_from('<QQ', h, 0x28)
    if not cso or not css:
        return b''
    fh.seek(cso)
    return fh.read(css)


res = {'macho': 0, 'slices': 0, 'dsc': 0, 'unsigned': [], 'bad_pages': [], 'in_tc': 0, 'not_in_tc': [],
       'tc_entries': len(tc)}
seen_inodes = set()
found_hashes = set()
t0 = time.time()
n = 0
for dp, dns, fns in os.walk(root):
    for fn in fns:
        p = os.path.join(dp, fn)
        rel = os.path.relpath(p, root)
        st = os.lstat(p)
        if not os.path.isfile(p) or os.path.islink(p) or st.st_size < 32:
            continue
        if st.st_ino in seen_inodes:
            continue
        seen_inodes.add(st.st_ino)
        with open(p, 'rb') as fh:
            is_dsc = False
            sl = macho_slices(fh, st.st_size)
            sigs = []
            if sl is not None:
                try:
                    for off, sz in sl:
                        sigs.append((off, sig_of_slice(fh, off)))
                except (ValueError, struct.error) as e:
                    res.setdefault('malformed', []).append([rel, st.st_size, str(e)])
                    continue
                res['macho'] += 1
                res['slices'] += len(sl)
            else:
                s = dsc_sig(fh)
                if s is None:
                    continue
                is_dsc = True
                res['dsc'] += 1
                sigs.append((0, s))
            file_in_tc = False
            for base, s in sigs:
                if not s:
                    res['unsigned'].append(rel)
                    continue
                cds = cds_of(s)
                best = None
                for cd in cds:
                    cdh, ht, ok, npg, why = check_cd(fh, base, cd)
                    if not ok:
                        res['bad_pages'].append([rel, base, why])
                        continue
                    if cdh in tc:
                        file_in_tc = True
                        found_hashes.add(cdh)
                    if best is None or ht == 2:
                        best = cdh
                if not cds:
                    res['unsigned'].append(rel)
            if file_in_tc:
                res['in_tc'] += 1
            elif sigs and any(s for _, s in sigs):
                res['not_in_tc'].append(rel + (' [dsc]' if is_dsc else ''))
        n += 1
        if n % 2000 == 0:
            print(f'{n} signed objects checked, {(time.time() - t0) / 60:.1f} min', flush=True)
res['tc_entries_matched'] = len(found_hashes)
res['tc_entries_unmatched'] = len(tc) - len(found_hashes)
res['minutes'] = round((time.time() - t0) / 60, 1)
json.dump(res, open(outp, 'w'), indent=1)
print({k: (v if not isinstance(v, list) else len(v)) for k, v in res.items()})
print('bad_pages sample', res['bad_pages'][:5])
print('not_in_tc sample', res['not_in_tc'][:15])
print('unsigned sample', res['unsigned'][:10])
