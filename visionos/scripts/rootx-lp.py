"""RealityLauncher: raise the Home view's long-press-to-edit threshold (EnterEditingModeViaLongPressViewModifier,
sub_1001AAB5C: DelayedLongPressGesture(minimumDuration: 0.5, maximumDistance: 10)). Measured 2026-11-08 on the TCG
guest: the launcher's main thread stalls 0.4-0.75 s (up to 2.5-3.7 s) right after touch-down, the touch-up waits in
the queue meanwhile and the 0.5 s timer fires first, so a 230-290 ms tap on an environment card becomes a long press
(edit mode, "Done") and the card's action never runs. Slow-machine accommodation, not a feature change: edit mode
still opens with a longer hold.
    rootx-lp.py ORIGINAL PATCHED [SECONDS]      SECONDS: 2.0 or 3.0 (default 3.0)
Re-sign afterwards with reattest.py and add the new CDHash to the trust cache.
"""
import struct, sys
VA = 0x1001aad6c                      # fmov d0, #0.5  (minimumDuration)
OLD = 0x1E6C1000                      # fmov d0, #0.5
NEXT = (0x1001aad70, 0x1E649001)      # fmov d1, #10.0 (maximumDistance), sanity check
NEW = {'2.0': 0x1E601000, '3.0': 0x1E611000}
secs = sys.argv[3] if len(sys.argv) > 3 else '3.0'
b = bytearray(open(sys.argv[1], 'rb').read())
magic, cpu, sub, ft, ncmds, sc, fl, _r = struct.unpack_from('<IIIIIIII', b, 0)
assert magic == 0xfeedfacf, hex(magic)
q = 32; segs = []
for _ in range(ncmds):
    c, s = struct.unpack_from('<II', b, q)
    if c == 0x19:
        name = b[q + 8:q + 24].rstrip(b'\0').decode()
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', b, q + 24)
        segs.append((name, vmaddr, vmsize, fileoff))
    q += s
def off(va):
    for name, a, s, fo in segs:
        if a <= va < a + s and name == '__TEXT':
            return va - a + fo
    raise SystemExit(f'{va:#x} not in __TEXT')
o = off(VA)
cur, = struct.unpack_from('<I', b, o)
nxt, = struct.unpack_from('<I', b, off(NEXT[0]))
print(f'file offset {o:#x}: {cur:#010x}, next {nxt:#010x}')
if nxt != NEXT[1]:
    raise SystemExit(f'unexpected next word {nxt:#x} (want {NEXT[1]:#x}): wrong binary?')
if cur != OLD and cur not in NEW.values():
    raise SystemExit(f'unexpected word {cur:#x}: wrong binary?')
struct.pack_into('<I', b, o, NEW[secs])
open(sys.argv[2], 'wb').write(b)
print(f'minimumDuration 0.5 -> {secs} s ({NEW[secs]:#010x}) -> {sys.argv[2]}')
