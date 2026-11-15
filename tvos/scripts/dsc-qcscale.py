"""tvOS 27.2 (24K122): QuartzCore's display-mode scale as on a real Apple TV, so one disk runs at 4K and 1080p.

    dsc-qcscale.py DSC_DIR OUT_DIR

-[CADisplayMode preferredScale] (QuartzCore, 0x18c4bfb2c in 24K122's shared cache, subcache .03):

    m = self->_mode;
    if (m[0x20]) return m[0x20];                            // a scale the render server set
    if (m[0] & 0x10000000) goto virtual;                    // a flag of the mode itself
    if (!MGGetBoolAnswer("IsVirtualDevice")) goto hardware; // cached once, the byte at 0x1ed606e51
    virtual:  return max(m[0x24], 2);
    hardware: return m[0x18] > 1080 ? 2 : 1;                // m[0x18]: the mode's height in lines

PineBoardServices takes that number as the mode's scale, so in this VM (IsVirtualDevice true) a 1920x1080
framebuffer became "1920x1080 at 2x" and tvOS drew 3840x2160 into it (the top left quarter shown). The b.ne after
the IsVirtualDevice test (0x18c4bfb70) becomes a b to the hardware rule: 1 for a 1920x1080 mode (which is why
m[0x18] is the height: the width, 1920, would give 2), 2 for a 3840x2160 one, which is what the virtual rule gave
there (4K was drawn at 2x before the patch, so m[0x24] <= 2). The two returns above the test stay as they are.

The subcache is found by its mappings (dsc-patch.py's file_offset); the function's 28 words must be 24K122's,
with the branch stock (patched by dsc-patch.py, which checks the word again and recomputes the touched page hash
in every CodeDirectory) or patched already. Prints "FILE OLD_CDHASH NEW_CDHASH" as dsc-patch.py does, or
"FILE CDHASH CDHASH already" (nothing written) for a cache that has the patch. The CDHashes are computed; the
pinned ones of 24K122's subcache are only checked against them.
"""
import importlib.util
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('dscpatch', os.path.join(HERE, 'dsc-patch.py'))
dp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dp)

FUNC_VA = 0x18c4bfb2c
SITE = 0x44                     # 0x18c4bfb70: b.ne <hardware rule>
STOCK, PATCHED = 'c1000054', '06000014'
# -[CADisplayMode preferredScale] from its pacibsp to its mov x0, x8 (the word at SITE stock)
FUNC = ('7f2303d5' 'ff8300d1' 'fd7b01a9' 'fd430091'      # pacibsp; frame
        '090440f9' '282140b9' 'a8020035'                 # ldr x9, [x0, #8]; ldr w8, [x9, #0x20]; cbnz w8, out
        '280d4039' '48012037'                            # ldrb w8, [x9, #3]; tbnz w8, #4, virtual
        '288a30f0' '082d47f9' '1f0500b1' '61020054'      # dispatch_once's token: b.ne once
        '288a30f0' '08457939' '090440f9' '1f050071'      # ldrb w8, IsVirtualDevice; ldr x9, [x0, #8]; cmp w8, #1
        'c1000054'                                       # b.ne hardware          -> b hardware
        '282540b9' '1f090071' '49008052' '0881891a'      # virtual: max(w[x9 + 0x24], 2)
        '05000014'                                       # b out
        '280d40f9' '1fe110f1' '28008052' '0895889a'      # hardware: x[x9 + 0x18] (height) > 1080 ? 2 : 1
        'e00308aa')                                      # out: mov x0, x8
# 24K122's subcache .03 before and after (cross-check only)
PIN = {'dyld_shared_cache_arm64e.03': ('a1d73d238b3ad533accf076e986c67b0619d2558',
                                       '06c5fb4333f2d91dfac4b03577bc8fc2f4ecb8ce')}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out = sys.argv[1], sys.argv[2]
    func = bytes.fromhex(FUNC)
    for name in sorted(os.listdir(src)):
        path = os.path.join(src, name)
        if not os.path.isfile(path):
            continue
        with open(path, 'rb') as f:
            head = f.read(0x4000)
            if not head.startswith(b'dyld_v1') or dp.file_offset(head, FUNC_VA) is None:
                continue
            fo = dp.file_offset(head, FUNC_VA)
            f.seek(fo)
            have = f.read(len(func))
        break
    else:
        sys.exit(f'qcscale: {FUNC_VA:#x} is in no subcache of {src}')
    site = have[SITE:SITE + 4].hex()
    if have[:SITE] != func[:SITE] or have[SITE + 4:] != func[SITE + 4:] or site not in (STOCK, PATCHED):
        sys.exit(f'qcscale: {name}+{fo:#x} is not 24K122\'s -[CADisplayMode preferredScale] (another tvOS build?): '
                 f'{have.hex()}')
    pin = PIN.get(name)
    if site == PATCHED:
        buf = open(path, 'rb').read()
        cds = dict(dp.cdhash(buf, cd) for cd in dp.code_directories(buf))
        h = cds[2 if 2 in cds else max(cds)]
        if pin and h != pin[1]:
            sys.exit(f'qcscale: {name} has the patch but CDHash {h}, not {pin[1]} (another change in it?)')
        print(name, h, h, 'already')
        return
    r = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'dsc-patch.py'), src, hex(FUNC_VA + SITE),
                        STOCK, PATCHED, out], capture_output=True, text=True)
    if r.returncode:
        sys.exit('qcscale: dsc-patch.py: ' + (r.stdout + r.stderr).strip())
    f, old, new = r.stdout.split()
    if f != name or (pin and (old, new) != pin):
        os.remove(os.path.join(out, f))
        sys.exit(f'qcscale: {f} CDHash {old} -> {new}, not 24K122\'s {pin} (removed; another subcache?)')
    print(name, old, new)
    print(f'qcscale: {name}+{fo + SITE:#x} b.ne -> b: the hardware scale rule (1080p 1x, 2160p 2x)', file=sys.stderr)


if __name__ == '__main__':
    main()
