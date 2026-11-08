"""Watch identity for the vresearch device tree: dtree-smp4 (iPhone 16 Research Device) with the
Series 9's product node, so MobileGestalt answers watch artwork (subtype 430, scale 2, idiom watch),
ProductType Watch7,1 (root model / compatible[1]) and launchd loads jetsamproperties.N207s.
The VM's own keys stay (phandle, guest-agent port, virtualization, gestalt variant, graphics
feature set = reims' APPLE7, framebuffer id); syscfg placeholders of the watch tree are dropped.
target-type/target-sub-type/compatible[0] stay VPHONE600 for the kernel's driver matching.
chosen/display-scale becomes 2 (boot with fb=352x430).

    dt-watch.py BASE_DTREE WATCH_RAW_ADT OUT
vresearch_dt_fixup comes from the qemu-sptm checkout (the iOS 26 install's tools\\qemu-sptm): set QEMU_SPTM
to it, as for dt-root26smp.py. WATCH_RAW_ADT is the watch IPSW's DeviceTree.n207sap.im4p, unwrapped.
"""
import os, sys
sys.path.insert(0, os.path.join(os.environ['QEMU_SPTM'], 'scripts', 'darwin'))
import vresearch_dt_fixup as dt

base, watch, out = sys.argv[1:4]
root, _ = dt.parse(open(base, 'rb').read())
wroot, _ = dt.parse(open(watch, 'rb').read())

KEEP_OURS = {'AAPL,phandle', 'name', 'apple-guest-agent-port', 'has-virtualization', 'gestalt-variant-id',
             'graphics-featureset-class', 'graphics-featureset-fallbacks',
             'variant-name', 'vm-supports-generative-models'}
p, wp = root.child('product'), wroot.child('product')
ours = dict(p.props)
p.props.clear()
for k, (f, v) in wp.props.items():
    if k in KEEP_OURS or v.startswith(b'syscfg/'):
        continue
    p.props[k] = (f, v)
for k in KEEP_OURS:
    if k in ours:
        p.props[k] = ours[k]
p.set('jetsam-properties-product-type', 'N207s')
p.set('thinning-product-type', 'Watch7,1')
# launchd loads driverkitd only with this key (_LimitLoadToDeviceTree product:supports-driverkit);
# without driverkitd no AppleUserHIDDrivers.dext, so the USB touchscreen, keyboard and buttons are no HID services
p.set('supports-driverkit', dt.u32(1))

# MobileGestalt reads vphone600-gestalt-variants' tags in place of syscfg on the VM; with D47's values the
# watch UI finds no screen class ("Unsupported screen class -1", the logo in a corner, PepperUICore's
# "Screen class invalid"). The same tags vphone-cli's devicetree-cfw-watch_presentation sets.
variant = next(c for c in p.children if b'gestalt-variants' in c.props['name'][1]).children[0]
def wv(k):
    return wp.props[k][1]
for tag, val in (('tag-ards', wv('artwork-device-subtype')), ('tag-arsf', wv('artwork-scale-factor')),
                 ('tag-codf', wv('compatible-device-fallback')), ('tag-tprt', b'Watch7,1\0'),
                 ('tag-crid', wv('chrome-identifier')), ('tag-dcrd', wv('display-corner-radius')),
                 ('tag-fbid', wv('framebuffer-identifier')), ('tag-prde', wv('product-description')),
                 ('tag-isnl', dt.u32(0)), ('tag-waco', dt.u32(0)), ('tag-jppt', b'N207s\0')):
    assert tag in variant.props, tag
    variant.props[tag] = (variant.props[tag][0], val)

root.set('model', 'Watch7,1')
f, comp = root.props['compatible']
parts = comp.split(b'\0')
parts[1] = b'Watch7,1'
root.props['compatible'] = (f, b'\0'.join(parts))
root.child('chosen').set('display-scale', dt.u32(2))

open(out, 'wb').write(dt.encode(root))
pr = p.props
print(f'wrote {out}: product {len(pr)} props, artwork {int.from_bytes(pr["artwork-device-subtype"][1], "little")} '
      f'@{int.from_bytes(pr["artwork-scale-factor"][1], "little")}x {pr["artwork-device-idiom"][1]!r}, '
      f'model {root.props["model"][1]!r}, compatible {root.props["compatible"][1]!r}')
