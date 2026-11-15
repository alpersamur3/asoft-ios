"""Apple TV 4K (AppleTV14,1, J255) identity for the vresearch device tree, as dt-watch.py does for the watch:
an SMP tree of the iOS 26 base (dtree-smp4, dtree-smp8, or dt-root26smp.py's output for 6) with J255's product
node, so MobileGestalt answers TV artwork (subtype 3840, scale 2, idiom tv), ProductType AppleTV14,1 (root model /
compatible[1]) and launchd loads jetsamproperties.J255. The VM's own keys stay (phandle, guest-agent port,
virtualization, gestalt variant, graphics feature set = reims' APPLE7, variant name); syscfg placeholders of
J255's tree are dropped. target-type/target-sub-type/compatible[0] stay VPHONE600 for the kernel's driver
matching. chosen/display-scale 2 (boot with fb=3840x2160, vphone-cli's validated 4K canvas). Product subnodes
(audio, maps) are copied.

The VM's keys go back into the product node in sorted order, so two runs give the same bytes (the hand-run
dt-tv.py of the first tvOS build iterated a set: its order followed Python's hash seed), as dt-vision.py does.

    dt-tv.py BASE_DTREE J255_RAW_ADT OUT
vresearch_dt_fixup comes from the qemu-sptm checkout (the iOS 26 install's tools\\qemu-sptm): set QEMU_SPTM to
it, as for dt-root26smp.py and dt-vision.py. J255_RAW_ADT is the OTA's DeviceTree.j255ap.im4p, unwrapped
(dtraw.py).
"""
import copy
import os
import sys

if not os.environ.get('QEMU_SPTM'):
    sys.exit('set QEMU_SPTM to the qemu-sptm checkout (its scripts/darwin/vresearch_dt_fixup.py)')
sys.path.insert(0, os.path.join(os.environ['QEMU_SPTM'], 'scripts', 'darwin'))
import vresearch_dt_fixup as dt  # noqa: E402

base, tv, out = sys.argv[1:4]
root, _ = dt.parse(open(base, 'rb').read())
troot, _ = dt.parse(open(tv, 'rb').read())

KEEP_OURS = ('AAPL,phandle', 'name', 'apple-guest-agent-port', 'has-virtualization', 'gestalt-variant-id',
             'graphics-featureset-class', 'graphics-featureset-fallbacks',
             'variant-name', 'vm-supports-generative-models')
p, tp = root.child('product'), troot.child('product')
ours = dict(p.props)
p.props.clear()
for k, (f, v) in tp.props.items():
    if k in KEEP_OURS or v.startswith(b'syscfg/') or v.startswith(b'macaddr/'):
        continue
    p.props[k] = (f, v)
for k in sorted(KEEP_OURS):
    if k in ours:
        p.props[k] = ours[k]
p.set('jetsam-properties-product-type', 'J255')
p.set('thinning-product-type', 'AppleTV14,1')
p.set('supports-driverkit', dt.u32(1))
names = {c.props['name'][1].rstrip(b'\0') for c in p.children}
for c in tp.children:
    if c.props['name'][1].rstrip(b'\0') not in names:
        p.children.append(copy.deepcopy(c))

variant = next(c for c in p.children if b'gestalt-variants' in c.props['name'][1]).children[0]


def tv_val(k, default):
    return tp.props[k][1] if k in tp.props else default


for tag, val in (('tag-ards', tv_val('artwork-device-subtype', dt.u32(3840))),
                 ('tag-arsf', tv_val('artwork-scale-factor', dt.u32(2))),
                 ('tag-codf', tv_val('compatible-device-fallback', b'AppleTV11,1\0')),
                 ('tag-tprt', b'AppleTV14,1\0'),
                 ('tag-crid', tv_val('chrome-identifier', b'com.apple.dt.devicekit.chrome.tv\0')),
                 ('tag-dcrd', tv_val('display-corner-radius', bytes(8))),
                 ('tag-fbid', tv_val('framebuffer-identifier', b'0\0')),
                 ('tag-prde', tv_val('product-description', b'Apple TV 4K (3rd generation)\0')),
                 ('tag-isnl', dt.u32(0)), ('tag-waco', dt.u32(0)), ('tag-jppt', b'J255\0')):
    assert tag in variant.props, tag
    variant.props[tag] = (variant.props[tag][0], val)

root.set('model', 'AppleTV14,1')
f, comp = root.props['compatible']
parts = comp.split(b'\0')
parts[1] = b'AppleTV14,1'
root.props['compatible'] = (f, b'\0'.join(parts))
root.child('chosen').set('display-scale', dt.u32(2))

open(out, 'wb').write(dt.encode(root))
pr = p.props
print(f'wrote {out}: product {len(pr)} props, artwork {int.from_bytes(pr["artwork-device-subtype"][1], "little")} '
      f'@{int.from_bytes(pr["artwork-scale-factor"][1], "little")}x {pr["artwork-device-idiom"][1]!r}, '
      f'model {root.props["model"][1]!r}, compatible {root.props["compatible"][1]!r}, '
      f'children {[c.props["name"][1].rstrip(bytes(1)) for c in p.children]}')
