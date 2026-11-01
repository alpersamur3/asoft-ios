"""Add CDHashes to a trust cache with the hash type, flags and constraint category of an entry
it already has: a patched binary's new CDHash next to its original's. mobileactivationd's keeps
the constraint category 3 of Apple's entry for it (README step 5.1), which mktc.py's text lists
cannot give (they get 0).

    tc-like.py OUT IN OLD_CDHASH NEW_CDHASH [NEW_CDHASH ...]

IN is a trust cache mktc.py reads (raw or IM4P, version 1 or 2) and must hold OLD_CDHASH; the old
entry stays. OUT is written as version 2, sorted, as mktc.py -2 writes it.
"""
import importlib.util, os, struct, sys


def mktc():
    spec = importlib.util.spec_from_file_location(
        'mktc', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mktc.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    out, src, old, new = sys.argv[1], sys.argv[2], sys.argv[3].lower(), [h.lower() for h in sys.argv[4:]]
    entries = mktc().read_tc(open(src, 'rb').read())
    like = entries.get(bytes.fromhex(old))
    if like is None:
        sys.exit(f'{old} is not in {src}')
    for h in new:
        if len(h) != 40:
            sys.exit(f'{h}: not a 40-digit CDHash')
        entries[bytes.fromhex(h)] = like
    buf = struct.pack('<I', 2) + b'A' * 16 + struct.pack('<I', len(entries))
    for h in sorted(entries):
        t, f, c = entries[h]
        buf += h + bytes([t, f, c, 0])
    open(out, 'wb').write(buf)
    print(f'{out}: version 2, {len(entries)} entries; {len(new)} added as {old} (type {like[0]}, '
          f'flags {like[1]}, category {like[2]})')


if __name__ == '__main__':
    main()
