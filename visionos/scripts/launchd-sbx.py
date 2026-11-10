"""launchd's mach-lookup gate on visionOS under the PCC kernel: the kernel's platform sandbox has no rules for
com.apple.polaris.*, com.apple.UXMSessionService, com.apple.wakeboard.* (vphone-cli PR #847 interposes
sandbox_check_by_audit_token in PID 1 for those names, read). Without an injected dylib: the __auth_stubs entry
of _sandbox_check_by_audit_token in /sbin/launchd becomes `mov w0,#0; ret`, so launchd allows every lookup.
Re-sign and trust-cache the result afterwards (reattest.py).

    launchd-sbx.py LAUNCHD [OUT]     without OUT: dry run, prints where the stub is
"""
import struct, sys
SYM = b'_sandbox_check_by_audit_token'
b = bytearray(open(sys.argv[1], 'rb').read())
magic, cpu, sub, ft, ncmds, sc, fl, _r = struct.unpack_from('<IIIIIIII', b, 0)
assert magic == 0xfeedfacf, hex(magic)
print(f'cpu {cpu:#x} sub {sub:#x} ncmds {ncmds}')
secs = []
symtab = dysym = None
q = 32
segs = []
for _ in range(ncmds):
    c, s = struct.unpack_from('<II', b, q)
    if c == 0x19:
        name = b[q + 8:q + 24].rstrip(b'\0')
        vm, vms, fo, fs, _m, _i, ns, _f = struct.unpack_from('<QQQQIIII', b, q + 24)
        segs.append((name, vm, vms, fo, fs))
        for i in range(ns):
            o = q + 72 + i * 80
            sn = b[o:o + 16].rstrip(b'\0')
            addr, size, off, al, ro, nr, flags, r1, r2, r3 = struct.unpack_from('<QQIIIIIIII', b, o + 32)
            secs.append((sn, name, addr, size, off, flags, r1, r2))
    elif c == 2:
        symtab = struct.unpack_from('<IIII', b, q + 8)
    elif c == 0xb:
        dysym = struct.unpack_from('<18I', b, q + 8)
    q += s
symoff, nsyms, stroff, strsize = symtab
indoff, nind = dysym[12], dysym[13]
print('sections', [(s[0], s[1], hex(s[2]), s[3]) for s in secs if b'stubs' in s[0]])
hits = []
for sn, seg, addr, size, off, flags, r1, r2 in secs:
    if (flags & 0xff) != 8:		# S_SYMBOL_STUBS
        continue
    stub = r2
    for i in range(size // stub):
        idx, = struct.unpack_from('<I', b, indoff + (r1 + i) * 4)
        if idx & 0xc0000000:
            continue
        nx, = struct.unpack_from('<I', b, symoff + idx * 16)
        e = b.index(0, stroff + nx)
        name = bytes(b[stroff + nx:e])
        if name == SYM:
            hits.append((sn, addr + i * stub, off + i * stub, stub))
print('hits', [(h[0], hex(h[1]), hex(h[2]), h[3]) for h in hits])
assert len(hits) == 1, 'expected one stub'
sn, va, fo, stub = hits[0]
print('stub bytes', bytes(b[fo:fo + stub]).hex())
new = bytes.fromhex('00008052c0035fd6') + bytes.fromhex('1f2003d5') * ((stub - 8) // 4)
print('new bytes ', new.hex())
if len(sys.argv) > 2:
    b[fo:fo + stub] = new
    open(sys.argv[2], 'wb').write(b)
    print('wrote', sys.argv[2])
