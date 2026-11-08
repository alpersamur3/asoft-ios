"""Always On Display in an iOS 26 device tree: a /arm-io/disp0 node with always-on-time.

    dt-aod.py IN_DTREE OUT_DTREE

libMobileGestalt answers DeviceSupportsAlwaysOnTime from whether a node named disp0 under
/arm-io has the property always-on-time (its value is not read); the research VM's tree has no
disp0. No kext matches disp0, so the node only reaches MobileGestalt. On its own it is not
enough: backboardd then takes the display for one with a hardware flipbook and asserts on the
paravirtual one (frame_info_enabled), so the disk needs root26-aod.py's libMobileGestalt patch
too (AlwaysOnDisplayFlipbook answered no). Idempotent: a tree that has disp0 is written as it is.

vresearch_dt_fixup comes from the qemu-sptm checkout (branch asoft): set QEMU_SPTM to it.
"""
import os, sys

if not os.environ.get('QEMU_SPTM'):
    sys.exit('set QEMU_SPTM to the qemu-sptm checkout (branch asoft)')
sys.path.insert(0, os.path.join(os.environ['QEMU_SPTM'], 'scripts', 'darwin'))
import vresearch_dt_fixup as dt


def phandles(n):
    p = n.props.get('AAPL,phandle')
    out = [int.from_bytes(p[1][:4], 'little')] if p else []
    for c in n.children:
        out += phandles(c)
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    root, _ = dt.parse(open(sys.argv[1], 'rb').read())
    arm_io = root.child('arm-io')
    if any(c.name == 'disp0' for c in arm_io.children):
        print('%s: /arm-io/disp0 is there already' % sys.argv[1])
    else:
        disp0 = dt.Node()
        disp0.set('name', 'disp0')
        disp0.set('AAPL,phandle', dt.u32(max(phandles(root)) + 1))
        disp0.set('always-on-time', dt.u32(1))
        arm_io.children.append(disp0)
        print('%s: /arm-io/disp0 always-on-time (phandle %#x)' % (sys.argv[2], max(phandles(root))))
    open(sys.argv[2], 'wb').write(dt.encode(root))


if __name__ == '__main__':
    main()
