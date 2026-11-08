"""The phone's device trees from the PC installers' (the Android app's setup in its helper VM, and
scripts/Send-ToPhone.ps1 -OS 26 / watchos):

    dt-phone.py IN OUT [--timebase HZ] [--ram-gib N]

--timebase: every /cpus/cpuN timebase-frequency (a u64) becomes HZ. The phone runs iOS 26 and the watch
  on its own counter (-cpu ...,x-host-counter=on), 19.2 MHz on Snapdragons, so the guest's clock and a
  quick boot's catch-up are right (ANDROID-S25.md 8.13: dtree-root26v-smp4-19m2, WATCHOS.md: dtree-w-3g-19m2).
--ram-gib: the guest's RAM: /chosen dram-size and the size in /memory reg become N GiB, and the base of
  /product/util's reg (the region right after RAM) moves with it (the watch's 3 GiB tree, dtree-w-3g).
Only those values change; the tree keeps its layout and size. Prints what it changed.
"""
import argparse, struct, sys


def nodes(b):
    """(path, {prop: (value offset, length)}) of every node, depth first"""
    out = []

    def walk(o, path):
        np_, nc = struct.unpack_from('<II', b, o)
        o += 8
        props, name = {}, '?'
        for _ in range(np_):
            n = b[o:o + 32].split(b'\0')[0].decode()
            ln = struct.unpack_from('<I', b, o + 32)[0] & 0x7fffffff
            props[n] = (o + 36, ln)
            if n == 'name':
                name = b[o + 36:o + 36 + ln].split(b'\0')[0].decode()
            o += 36 + ((ln + 3) & ~3)
        here = path + '/' + name if path else name
        out.append((here, props))
        for _ in range(nc):
            o = walk(o, here)
        return o

    end = walk(0, '')
    if end != len(b):
        sys.exit('the tree is %d bytes, its nodes end at %d: not an ADT?' % (len(b), end))
    return out


def main():
    a = argparse.ArgumentParser()
    a.add_argument('inp')
    a.add_argument('out')
    a.add_argument('--timebase', type=int)
    a.add_argument('--ram-gib', type=int)
    o = a.parse_args()
    b = bytearray(open(o.inp, 'rb').read())
    tree = nodes(b)
    done = []

    def put64(path, prop, off, value):
        old = struct.unpack_from('<Q', b, off)[0]
        struct.pack_into('<Q', b, off, value)
        done.append('%s %s: %#x -> %#x' % (path, prop, old, value))

    if o.timebase:
        n = 0
        for path, props in tree:
            if '/cpus/' in path and 'timebase-frequency' in props:
                off, ln = props['timebase-frequency']
                if ln != 8:
                    sys.exit('%s timebase-frequency is %d bytes, not 8' % (path, ln))
                put64(path, 'timebase-frequency', off, o.timebase)
                n += 1
        if not n:
            sys.exit('no /cpus/*/timebase-frequency in %s' % o.inp)
    if o.ram_gib:
        size = o.ram_gib << 30
        found = {}
        for path, props in tree:
            leaf = path.rsplit('/', 1)[-1]
            if leaf == 'chosen' and 'dram-size' in props:
                found['chosen'] = (path, props['dram-size'])
            elif leaf == 'memory' and 'reg' in props:
                found['memory'] = (path, props['reg'])
            elif path.endswith('/product/util') and 'reg' in props:
                found['util'] = (path, props['reg'])
        for k in ('chosen', 'memory', 'util'):
            if k not in found:
                sys.exit('no %s in %s' % (k, o.inp))
        path, (off, ln) = found['chosen']
        put64(path, 'dram-size', off, size)
        path, (off, ln) = found['memory']
        base = struct.unpack_from('<Q', b, off)[0]
        put64(path, 'reg size', off + 8, size)
        path, (off, ln) = found['util']
        put64(path, 'reg base', off, base + size)
    open(o.out, 'wb').write(b)
    for d in done:
        print(d)


if __name__ == '__main__':
    main()
