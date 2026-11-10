"""Vision Pro identity for the vresearch device tree, as dt-watch.py does for the watch: an SMP tree of the
iOS 26 install (dtree-smp4, dtree-smp8, or dt-root26smp.py's output for 6) with the N301AP product node,
ProductType RealityDevice14,1, jetsam N301. The VM's own keys stay (phandle, guest-agent port,
virtualization, gestalt variant, graphics feature set = reims' APPLE7, framebuffer id); syscfg placeholders
are dropped. target-type/target-sub-type/compatible[0] stay VPHONE600 for the kernel's driver matching
(arkitd, realitycamerad, makod load only on target-type N301/N301a, so they stay out).

product-id is V201: vphone-cli PR #847 (OnyxAxisOwO, read, for 23O247): the MobileGestalt entry 0x90532c43 is
virtual and wakeboardd maps it to its V201HMD/IOMobileFramebuffer path; other tokens are rejected.

The VM's keys go back into the product node in sorted order, so two runs give the same bytes (the hand-run
version iterated a set: the order followed Python's hash seed).

    dt-vision.py BASE_DTREE N301AP_RAW_ADT OUT
vresearch_dt_fixup comes from the qemu-sptm checkout (the iOS 26 install's tools\\qemu-sptm): set QEMU_SPTM
to it, as for dt-root26smp.py. N301AP_RAW_ADT is the IPSW's DeviceTree.n301ap.im4p, unwrapped.
"""
import base64, os, sys

if not os.environ.get('QEMU_SPTM'):
    sys.exit('set QEMU_SPTM to the qemu-sptm checkout (its scripts/darwin/vresearch_dt_fixup.py)')
sys.path.insert(0, os.path.join(os.environ['QEMU_SPTM'], 'scripts', 'darwin'))
import vresearch_dt_fixup as dt

V201 = base64.b64decode('Z/7NpsIWJyzM76tqwMpW0t8Ep6E=')
base, vision, out = sys.argv[1:4]
root, _ = dt.parse(open(base, 'rb').read())
vroot, _ = dt.parse(open(vision, 'rb').read())

KEEP_OURS = ('AAPL,phandle', 'name', 'apple-guest-agent-port', 'has-virtualization', 'gestalt-variant-id',
             'graphics-featureset-class', 'graphics-featureset-fallbacks',
             'variant-name', 'vm-supports-generative-models')
p, vp = root.child('product'), vroot.child('product')
ours = dict(p.props)
old_id = ours.get('product-id', (0, b''))[1]
p.props.clear()
for k, (f, v) in vp.props.items():
    if k in KEEP_OURS or v.startswith(b'syscfg/'):
        continue
    p.props[k] = (f, v)
for k in sorted(KEEP_OURS):
    if k in ours:
        p.props[k] = ours[k]
assert len(p.props['product-id'][1]) == len(V201)
p.props['product-id'] = (p.props['product-id'][0], V201)
p.set('jetsam-properties-product-type', 'N301')
p.set('thinning-product-type', 'RealityDevice14,1')
# visionOS's real tree says exclaves off; keep it stated in the product node as the N301AP tree does
for k in ('exclaves-enabled', 'has-exclaves'):
    assert int.from_bytes(p.props[k][1], 'little') == 0, k

# gestalt variant tags, in place of syscfg on the VM (the same tags as dt-watch.py); keep ours where N301AP has no value
variant = next(c for c in p.children if b'gestalt-variants' in c.props['name'][1]).children[0]
vals = {'tag-ards': 'artwork-device-subtype', 'tag-arsf': 'artwork-scale-factor', 'tag-codf': 'compatible-device-fallback',
        'tag-crid': 'chrome-identifier', 'tag-fbid': 'framebuffer-identifier', 'tag-prde': 'product-description'}
for tag, src in vals.items():
    if tag in variant.props and src in vp.props:
        variant.props[tag] = (variant.props[tag][0], vp.props[src][1])
for tag, val in (('tag-tprt', b'RealityDevice14,1\0'), ('tag-isnl', dt.u32(0)), ('tag-waco', dt.u32(0)), ('tag-jppt', b'N301\0')):
    if tag in variant.props:
        variant.props[tag] = (variant.props[tag][0], val)

root.set('model', 'RealityDevice14,1')
f, comp = root.props['compatible']
parts = comp.split(b'\0')
parts[1] = b'RealityDevice14,1'
root.props['compatible'] = (f, b'\0'.join(parts))
root.child('chosen').set('display-scale', dt.u32(1))

open(out, 'wb').write(dt.encode(root))
pr = p.props
print(f'wrote {out}: product {len(pr)} props, product-id {old_id.hex()} -> {pr["product-id"][1].hex()}, '
      f'artwork {int.from_bytes(pr["artwork-device-subtype"][1], "little")} @{int.from_bytes(pr["artwork-scale-factor"][1], "little")}x {pr["artwork-device-idiom"][1]!r}, '
      f'model {root.props["model"][1]!r}, compatible {root.props["compatible"][1]!r}')
print('variant tags', {k: v[1][:24] for k, v in variant.props.items() if k.startswith('tag-')})
