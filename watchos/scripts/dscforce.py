# iOS 27 IOMobileFramebuffer force-kern for the paravirt scanout (vphone-cli's iomfb_force_kern):
# every public _IOMobileFramebufferSwap<Op> that is a thin trampoline
#     cbz x0,fail; ldr xN,[x0,#slot]; cbz xN,fail; braaz xN
# and has both _kern_Swap<Op> and _virt_Swap<Op> becomes
#     cbz x0,fail; ldr w16,[x0,#0x14]; cbnz w16,_kern_Swap<Op>; b _virt_Swap<Op>
# (0x14 = the IOConnect port _kern_Swap* pass to io_connect_method). All sites go into one copy of
# the subcache with the touched page hashes recomputed, as dsc-patch.py does for one site.
#   python3 -I dscforce.py DSC_DIR SYMS_TXT OUT_DIR [--dry]
import hashlib
import importlib.util
import os
import struct
import sys

# ios26's dsc-patch.py, next to this script in the install's scripts folder
spec = importlib.util.spec_from_file_location(
    'dscpatch', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dsc-patch.py'))
dp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dp)

src, syms, out = sys.argv[1], sys.argv[2], sys.argv[3]
dry = '--dry' in sys.argv
PFX = {'P': '_IOMobileFramebufferSwap', 'K': '_kern_Swap', 'V': '_virt_Swap'}

ops = {}
for line in open(syms):
    f = line.split()
    if len(f) < 3:
        continue
    va, name = int(f[0].rstrip(':'), 16), f[2]
    for k, p in PFX.items():
        if name.startswith(p):
            ops.setdefault(name[len(p):], {})[k] = va
pairs = sorted((op, d) for op, d in ops.items() if len(d) == 3)

# the subcache that holds the trampolines
files = {}
for n in sorted(os.listdir(src)):
    p = os.path.join(src, n)
    with open(p, 'rb') as fh:
        h = fh.read(0x4000)
    if h.startswith(b'dyld_v1') and dp.file_offset(h, pairs[0][1]['P']) is not None:
        files[n] = p
name, path = next(iter(files.items()))
buf = bytearray(open(path, 'rb').read())
orig = bytes(buf)


def word(va):
    fo = dp.file_offset(buf, va)
    assert fo is not None, hex(va)
    return struct.unpack_from('<I', buf, fo)[0]


def sx(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


kern_end = [word(ops['End']['K'] + 4 * i) for i in range(32)]
print('_kern_SwapEnd ldr w0,[x0,#0x14]:', 0xb9401400 in kern_end)
assert 0xb9401400 in kern_end, 'port offset is not 0x14'

patches = []
for op, d in pairs:
    P, K, V = d['P'], d['K'], d['V']
    w = [word(P + 4 * i) for i in range(4)]
    ws = ' '.join(f'{x:08x}' for x in w)
    if w[1] == 0xb9401410 and (w[2] & 0xff00001f) == 0x35000010 and (w[3] & 0xfc000000) == 0x14000000:
        print(f'  = {op:22} already conditional')
        continue
    ok = (w[0] & 0xff00001f) == 0xb4000000                      # cbz x0
    n = w[1] & 31
    ok = ok and (w[1] & 0xffc003e0) == 0xf9400000 and (w[1] >> 10) & 0xfff  # ldr xN,[x0,#imm!=0]
    ok = ok and w[2] & 0xff00001f == 0xb4000000 | n             # cbz xN
    ok = ok and w[3] in (0xd61f081f | n << 5, 0xd61f0000 | n << 5) or ok and (w[3] & 0xfffffc1f) == (0xd71f0800 | n << 5) & 0xfffffc1f
    if not ok:
        print(f'  ? {op:22} {P:#x}: not a trampoline: {ws}')
        continue
    cbnz = 0x35000010 | (((K - (P + 8)) >> 2) & 0x7ffff) << 5
    b = 0x14000000 | (((V - (P + 12)) >> 2) & 0x3ffffff)
    new = struct.pack('<4I', w[0], 0xb9401410, cbnz, b)
    fail = P + 4 * sx((w[0] >> 5) & 0x7ffff, 19)
    print(f'  + {op:22} {P:#x}: {ws} -> {new.hex()}  kern {K:#x} virt {V:#x} fail {fail:#x}')
    patches.append((dp.file_offset(buf, P), new))

if dry or not patches:
    sys.exit(0)
for fo, new in patches:
    buf[fo:fo + len(new)] = new
before = dict(dp.cdhash(orig, cd) for cd in dp.code_directories(orig))
for cd in dp.code_directories(buf):
    hash_off, = struct.unpack_from('>I', buf, cd + 16)
    nslots, code_limit = struct.unpack_from('>II', buf, cd + 28)
    version, = struct.unpack_from('>I', buf, cd + 8)
    if version >= 0x20300 and code_limit == 0:
        code_limit, = struct.unpack_from('>Q', buf, cd + 56)
    hsize, htype, pshift = buf[cd + 36], buf[cd + 37], buf[cd + 39]
    ps = 1 << pshift
    pages = sorted({i for fo, new in patches for i in range(fo // ps, (fo + len(new) - 1) // ps + 1)})
    for i in pages:
        a, e = i * ps, min((i + 1) * ps, code_limit)
        slot = slice(cd + hash_off + i * hsize, cd + hash_off + (i + 1) * hsize)
        assert hashlib.new(dp.HASHES[htype], orig[a:e]).digest()[:hsize] == bytes(buf[slot]), 'stale page hash'
        buf[slot] = hashlib.new(dp.HASHES[htype], bytes(buf[a:e])).digest()[:hsize]
after = dict(dp.cdhash(buf, cd) for cd in dp.code_directories(buf))
os.makedirs(out, exist_ok=True)
open(os.path.join(out, name), 'wb').write(buf)
best = 2 if 2 in after else max(after)
print(name, before[best], after[best], f'{len(patches)} sites')
