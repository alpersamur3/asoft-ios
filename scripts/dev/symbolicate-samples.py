#!/usr/bin/env python3
"""Symbolicate SWEET sampler lines ("SMP name[pid] slide ... mh ..." + "SMP name tN pc .. lr .. sp .. bt ..").

  symbolicate-samples.py CACHE SAMPLES.txt [PROCESS]

Prints the last sample of each thread of PROCESS (default SpringBoard) with shared-cache
addresses resolved through `ipsw dyld a2s` (unslid by the header line's slide) and main-binary
addresses as offsets from its Mach-O header. Runs in the ios-emu WSL distro.
"""
import re, subprocess, sys

CACHE_LO, CACHE_HI = 0x180000000, 0x300000000
cache, samples = sys.argv[1], sys.argv[2]
proc = sys.argv[3] if len(sys.argv) > 3 else 'SpringBoard'

slide = mh = None
threads = {}
for text in open(samples, errors='replace'):
    # Console lines from several CPUs can run together: split at every "SMP ".
    for line in re.split(r'(?=SMP )', text):
        m = re.match(rf'SMP {re.escape(proc)}\[\d+\] slide (0x[0-9a-f]+) mh (0x[0-9a-f]+)', line)
        if m:
            slide, mh = int(m.group(1), 16), int(m.group(2), 16)
            continue
        m = re.match(rf'SMP {re.escape(proc)} (t\d+) (.*)', line)
        if m:
            threads[m.group(1)] = m.group(2)

memo = {}


def name(addr):
    if CACHE_LO <= addr - slide < CACHE_HI:
        key = addr - slide
        if key not in memo:
            r = subprocess.run(['ipsw', 'dyld', 'a2s', cache, hex(key)], capture_output=True, text=True)
            out = [l for l in (r.stdout + r.stderr).splitlines() if l.startswith('0x')]
            memo[key] = out[-1].split(': ', 1)[-1] if out else '?'
        return memo[key]
    if mh and 0 <= addr - mh < 0x10000000:
        return f'{proc}+0x{addr - mh + 0x100000000:x}'
    return '?'


print(f'{proc}: slide 0x{slide:x} mh 0x{mh:x}')
for tid in sorted(threads, key=lambda t: int(t[1:])):
    words = threads[tid].split()
    regs = dict(zip(words[0:6:2], words[1:6:2]))
    # Lines from several CPUs can interleave: keep only clean hex words
    tail = words[words.index('bt') + 1:] if 'bt' in words else []
    bt = [int(w, 16) for w in tail if re.fullmatch(r'0x[0-9a-f]+', w)]
    print(f'--- {tid}')
    for label, addr in [('pc', int(regs.get('pc', '0x0'), 16)), ('lr', int(regs.get('lr', '0x0'), 16))] + \
            [(f'#{i}', a) for i, a in enumerate(bt[:12])]:
        if addr:
            print(f'  {label:>3} 0x{addr:x}  {name(addr)}')
