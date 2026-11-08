# Find HEX (bytes seen at runtime) in a dyld shared cache's subcaches; print the subcache, the
# cache VA of each hit and the instruction words around it, flagging cmn w0,#1 and b.eq.
#   python3 -I dscfind.py DSC_DIR HEX [BEFORE_BYTES]
import mmap
import os
import struct
import sys

d, blob = sys.argv[1], bytes.fromhex(sys.argv[2])
before = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x80
for name in sorted(os.listdir(d)):
    p = os.path.join(d, name)
    with open(p, 'rb') as f:
        if f.read(7) != b'dyld_v1':
            continue
        m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    moff, mcount = struct.unpack_from('<II', m, 0x10)
    maps = [struct.unpack_from('<QQQ', m, moff + 32 * i) for i in range(mcount)]
    i = m.find(blob)
    while i >= 0:
        va = next((a + i - fo for a, s, fo in maps if fo <= i < fo + s), None)
        print(f'{name} file {i:#x} va {va:#x}' if va else f'{name} file {i:#x} (no mapping)')
        for o in range(i - before, i + len(blob), 4):
            w, = struct.unpack_from('<I', m, o)
            tag = ''
            if w & 0xff00001f == 0x54000000:
                tag = '  b.eq'
            elif w & 0xfffffc1f == 0x3100041f:
                tag = '  cmn w,#1'
            elif w & 0xfc000000 == 0x94000000:
                tag = '  bl'
            elif w in (0xd65f0fff, 0xd65f03c0):
                tag = '  ret'
            elif w == 0xd503237f:
                tag = '  pacibsp'
            print(f'  {va - i + o:#x}: {w:08x}{tag}' if va else f'  {o:#x}: {w:08x}{tag}')
        i = m.find(blob, i + 1)
    m.close()
