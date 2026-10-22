"""The device tree of a board from an IPSW, unpacked: what tools/mkadt.py takes /product from.

    ipsw-devicetree.py IPSW OUT.adt [--board d22ap]

Reads Firmware/all_flash/DeviceTree.<board>.im4p from the IPSW (a zip) and writes its
payload, decompressed (LZFSE) when it is. Plain Python: runs with the installer's Python on
Windows. The result is Apple's: keep it on this PC, out of the repository.
"""
import argparse, os, sys, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lzfse  # noqa: E402


def der(blob, pos):
    """(tag, content start, content end) of the DER item at pos."""
    tag, n = blob[pos], blob[pos + 1]
    pos += 2
    if n & 0x80:
        size = int.from_bytes(blob[pos:pos + (n & 0x7f)], 'big')
        pos += n & 0x7f
    else:
        size = n
    return tag, pos, pos + size


def im4p_payload(blob):
    """An IM4P: SEQUENCE { "IM4P", type, description, OCTET STRING payload, ... }"""
    tag, pos, end = der(blob, 0)
    if tag != 0x30:
        raise SystemExit('not an IM4P (no DER sequence)')
    items = []
    while pos < end:
        tag, start, pos = der(blob, pos)
        items.append((tag, blob[start:pos]))
    if len(items) < 4 or items[0] != (0x16, b'IM4P') or items[3][0] != 0x04:
        raise SystemExit('not an IM4P')
    return items[1][1].decode(), items[3][1]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('ipsw')
    ap.add_argument('out')
    ap.add_argument('--board', default='d22ap', help='the device tree to take (default d22ap)')
    a = ap.parse_args()
    member = f'Firmware/all_flash/DeviceTree.{a.board}.im4p'
    with zipfile.ZipFile(a.ipsw) as z:
        kind, payload = im4p_payload(z.read(member))
    if kind != 'dtre':
        raise SystemExit(f'{member}: an IM4P of type {kind}, not a device tree')
    if payload[:3] == b'bvx':
        payload = lzfse.decompress(payload)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out + '.part', 'wb') as f:
        f.write(payload)
    os.replace(a.out + '.part', a.out)
    print(f'{a.out}: {len(payload)} bytes ({member})')


if __name__ == '__main__':
    main()
