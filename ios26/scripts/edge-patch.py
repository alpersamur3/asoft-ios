"""UIKit's edge type for touches of a digitizer whose firmware sets no edge bits: the home
gesture, the app switcher and the edge swipe back on the QEMU touchscreen (iOS 26.6.2, 23G90;
the addresses are that build's).

    edge-patch.py DSC_DIR OUT_DIR

UIKitCore reads a touch's edge type only from the digitizer event mask's FromEdgeTip, FromCorner
and SwipePending bits, which Apple's touch firmware sets for a contact that starts at a panel edge
and which our USB touchscreen's driver (AppleUserHIDEventDriver) never sets. edge-cave.s, in the
zero padding after UIKitCore's __TEXT (0x18b66b640), answers 1 (FromEdgeTip) for a contact that
starts within 3.5 % of the left or right edge or 2 % of the top or bottom one and keeps it for
the contact's life; the one call in _UITouchSetBasicTouchPropertiesFromEvent goes there.
Writes OUT_DIR/dyld_shared_cache_arm64e.03 (from DSC_DIR's, unpatched) through dsc-patch.py and
prints its new CDHash, which goes into the trust cache; the subcache goes into the image as
apply-apps.sh writes .42 (cat >, keeping the hard link).
"""
import os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CAVE_VA = 0x18b66b640
CALL_VA = 0x1896dc92c       # bl __UIEventHIDTouchEdgeTypeForHIDEvent -> bl CAVE_VA
# edge-cave.hex: edge-cave.s assembled and linked at CAVE_VA (llvm-mc -triple=aarch64
# -mattr=+pauth; ld.lld -Ttext=0x18b66b640 --defsym=orig_edge_type=0x1896df8d4
# --defsym=get_integer=0x18d81b100 --defsym=get_float=0x18d81b0f0; llvm-objcopy -O binary)


def run(src, va, old, new, out):
    r = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'dsc-patch.py'), src, hex(va),
                        old, new, out], capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stdout + r.stderr)
    return r.stdout.split()


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out = sys.argv[1], sys.argv[2]
    cave = open(os.path.join(HERE, 'edge-cave.hex')).read().strip()
    os.makedirs(out, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out) as tmp:
        run(src, CAVE_VA, '00' * (len(cave) // 2), cave, tmp)
        name, _, new = run(tmp, CALL_VA, 'ea0b0094', '453b7e94', out)
    print('%s %s (add this CDHash to the trust cache)' % (name, new))


if __name__ == '__main__':
    main()
