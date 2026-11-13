"""The 1080p sibling of a tvOS device tree (dt-tv.py's): the same tree with tvOS's 1080p display keys.
tvOS lays out 1920x1080 points: a 4K Apple TV draws them at scale 2 into 3840x2160 (dt-tv.py's tree: artwork
subtype 3840, scale 2), at 1080p at scale 1 (artwork subtype 1080, scale 1). Changed: chosen/display-scale, the
product's artwork-device-subtype and artwork-scale-factor, and the gestalt variant's tags for them (tag-ards,
tag-arsf), which MobileGestalt answers from. Every other byte stays, in its order. Boot it with fb=1920x1080; the
disk needs QuartzCore's display-mode scale as on a real Apple TV (dsc-qcscale.py), else tvOS still takes the
1080p mode at scale 2 and draws 3840x2160 into it.

    dt-res.py TV_DTREE SCALE OUT        (SCALE 1: 1080p, 2: 4K)
vresearch_dt_fixup comes from the qemu-sptm checkout, as for dt-tv.py: set QEMU_SPTM to it.
"""
import os
import sys

if not os.environ.get('QEMU_SPTM'):
    sys.exit('set QEMU_SPTM to the qemu-sptm checkout (its scripts/darwin/vresearch_dt_fixup.py)')
sys.path.insert(0, os.path.join(os.environ['QEMU_SPTM'], 'scripts', 'darwin'))
import vresearch_dt_fixup as dt  # noqa: E402

if len(sys.argv) != 4 or sys.argv[2] not in ('1', '2'):
    sys.exit(__doc__)
src, scale, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
sub = 3840 if scale == 2 else 1080
root, _ = dt.parse(open(src, 'rb').read())
p = root.child('product')
if p.props.get('artwork-device-idiom', (0, b''))[1].rstrip(b'\0') != b'tv':
    sys.exit(f'{src}: its product node is no TV\'s (artwork-device-idiom); make it with dt-tv.py first')
root.child('chosen').set('display-scale', dt.u32(scale))
for k, v in (('artwork-device-subtype', sub), ('artwork-scale-factor', scale)):
    assert k in p.props, k
    p.props[k] = (p.props[k][0], dt.u32(v))
variant = next(c for c in p.children if b'gestalt-variants' in c.props['name'][1]).children[0]
for tag, v in (('tag-ards', sub), ('tag-arsf', scale)):
    assert tag in variant.props, tag
    variant.props[tag] = (variant.props[tag][0], dt.u32(v))
open(out, 'wb').write(dt.encode(root))
print(f'wrote {out}: display-scale {scale}, artwork subtype {sub} @{scale}x')
