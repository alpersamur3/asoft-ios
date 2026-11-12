"""Index the decrypted OTA (outer AA01 archive) recursively.

Top level = metadata entries (LBL + YOP) whose DAT blob holds a nested AA stream (stored, not compressed,
in the samples so far). For each nested regular file record: path, absolute data offset, size.
usage: index_outer.py OTA AA_DIR OUT.json
"""
import json
import sys

sys.path.insert(0, sys.argv[2])
import aa  # noqa: E402

path = sys.argv[1]
top, files = [], []


class Window:
    """File window [start, end) with .read(n)."""

    def __init__(self, fh, start, end):
        self.fh, self.pos, self.end = fh, start, end

    def read(self, n):
        n = max(0, min(n, self.end - self.pos))
        self.fh.seek(self.pos)
        b = self.fh.read(n)
        self.pos += len(b)
        return b

    def skip(self, n):
        self.pos += n


def walk(fh, start, end, label, depth):
    w = Window(fh, start, end)
    r = aa.Reader(w)
    for f, blobs, off in r.entries():
        typ = chr(f['TYP']) if isinstance(f.get('TYP'), int) else '?'
        yop = chr(f['YOP']) if isinstance(f.get('YOP'), int) else None
        rec = {'depth': depth, 'label': f.get('LBL', label), 'typ': typ, 'yop': yop, 'pat': f.get('PAT'),
               'off': start + off, 'blobs': []}
        for key, sz in blobs:
            boff = w.pos
            w.fh.seek(boff)
            head = w.fh.read(min(8, sz))
            rec['blobs'].append([key, sz, boff, head.hex()])
            if key == 'DAT' and typ == 'M' and head[:4] in (b'AA01', b'YAA1'):
                walk(fh, boff, boff + sz, rec['label'], depth + 1)
            elif key == 'DAT' and typ == 'F':
                files.append({'pat': rec['pat'], 'off': boff, 'size': sz, 'head': head.hex(),
                              'label': rec['label']})
            w.skip(sz)
            r.pos += sz
        top.append(rec)


with open(path, 'rb') as fh:
    fh.seek(0, 2)
    walk(fh, 0, fh.tell(), None, 0)
json.dump({'records': top, 'files': files}, open(sys.argv[3], 'w'), indent=0)
print(len(top), 'records,', len(files), 'files')
for t in top:
    if t['depth'] == 0:
        print(t['label'], t['yop'], [(b[0], b[1], b[3]) for b in t['blobs']])
