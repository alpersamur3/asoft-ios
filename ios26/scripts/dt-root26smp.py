"""SMP device tree for the HFS+ root (root26): vresearch_dt_fixup with
--cpus N, then the root26 tweaks (as dt-root26.py), plus A = no-effaceable
-storage (keybag chain) and /chosen/machine-timeouts/global-scale=100 (so the
kernel's ticket-spinlock timeout doesn't panic under SMP on a slow host, as in
iOS 16). Non-diag, SEP off.

    dt-root26smp.py RAW_ADT OUT [--cpus N]     (default N=2)

vresearch_dt_fixup comes from the qemu-sptm checkout (branch ios26): set QEMU_SPTM to it.
"""
import os, sys

if not os.environ.get('QEMU_SPTM'):
    sys.exit('set QEMU_SPTM to the qemu-sptm checkout (branch ios26)')
sys.path.insert(0, os.path.join(os.environ['QEMU_SPTM'], 'scripts', 'darwin'))
import vresearch_dt_fixup as dt

argv = sys.argv[1:]
ncpus = 2
if '--cpus' in argv:
    i = argv.index('--cpus'); ncpus = int(argv[i + 1]); del argv[i:i + 2]
raw, out = argv[0], argv[1]


def phandles(n):
    if 'AAPL,phandle' in n.props:
        yield int.from_bytes(n.props['AAPL,phandle'][1][:4], 'little')
    for c in n.children:
        yield from phandles(c)


root, _ = dt.parse(open(raw, 'rb').read())
dt.fixup(root, dt.DRAM_BASE, dt.DRAM_SIZE, ncpus, False, dt.empty_nvram(),
         display_scale=3, no_effaceable_storage=True, timeout_scale=100)

# --- root26 tweaks (same as dt-root26.py) ---
root.remove('filesystems')
chosen = root.child('chosen')
chosen.remove('asmb')
asmb = dt.Node()
asmb.set('name', 'asmb')
asmb.set('AAPL,phandle', dt.u32(max(phandles(root)) + 1))
asmb.set('lp-sip0', dt.u64(0x6f))
asmb.set('lp-sip1', dt.u32(1))
chosen.children.append(asmb)
chosen.set('chip-id', dt.u32(0x8142))
chosen.set('board-id', dt.u32(0x04))
uci = chosen.props.get('unique-chip-id')
if not uci or int.from_bytes(uci[1], 'little') == 0:
    chosen.set('unique-chip-id', dt.u64(0x0000a50100000001))

# display-scale=3, no-effaceable-storage=1 and machine-timeouts/global-scale=100
# are set by fixup() above (display_scale / no_effaceable_storage / timeout_scale).

open(out, 'wb').write(dt.encode(root))
print('wrote %s  cpus=%d  (chosen children: %s)'
      % (out, ncpus, [c.name for c in chosen.children]))
