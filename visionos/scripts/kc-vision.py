"""The visionOS kernelcache: cloudOS 26.4b's research kernel (the iOS 26 install's plain kernel, decompressed,
unpatched) with the iOS 27 userland's patches, the IOGPU timeouts and the sandbox syscall filters off, each
checked against the stock bytes first and the result against its SHA-256. A file other than that kernel is
refused. The result is byte for byte the hand-built bootkc-y (iOS 27's bootkc, then bootkc-x's three IOGPU words,
then kc-sfo.py), whose SHA-256 is pinned below.

  iOS 27 (as kc-watch.py, without the watch's Sandbox hook; vphone-cli's research names):
  - IOMobileFramebuffer user client: checkStructureInputSize 0x588 -> any, SwapEnd's cmp w2,#0x588 -> #0x6e0
  - kernel-boot-container_manager_upcall (JB-02d): the cbz after the upcall becomes a b to success
  - kernel-boot-shared_region_size: the arm64 shared region 0x1C0000000 at 0x180000000, for 27.x's cache
  - kernel-boot-iouc_sandbox_gate (JB-10b): "IOUC %s failed sandbox" goes to the allow path
  IOGPU (visionOS's 3D compositor waits longer than the stock 5 s under TCG):
  - the shared-event wait's clock_interval_to_deadline(5 s) -> 600 s
  - IOGPUScheduler's waitForGPUTimeoutSeconds (two loads of [x,#0x23c]) -> 600
  Sandbox syscall filters off (vphone-cli's kernel-exp-frida_syscall_filter_off): every per-process syscall
  mask reads "no filter", so visionOS 27 code the 26.4 profiles do not know is not killed (backboardd's
  socket_delegate after an environment change, audiomxd's Autobox); file, mach-lookup and IOKit rules stay:
  - task_get_mach_trap_filter_mask, task_get_mach_kobj_filter_mask -> mov x0,#0; ret
  - mac_proc_check_syscall_unix -> mov w0,#0; ret

    kc-vision.py OUT IN [IN ...]     the first IN that is the stock (or the visionOS) kernel, patched into OUT
    kc-vision.py --check IN [IN ...]  only names it (exit 1 when none is)

The iOS 26 install has the stock kernel as cloud/kernelcache.research.vphone600.decompressed; its fw/bootkc
is that file too, unless its gpu step rewrote it with kc-gles.py, which this refuses.
"""
import hashlib, os, sys

STOCK = '86895a2eebeb7fcfb68bcd60f2d7e685687faea07ee31166fb58c872b38e0d92'
VISION = '6f421a9a1929f2dc661919ab344fd70813dd496fadbf556cffd5ce6d49ac415d'
PATCHES = [   # file offset, stock bytes, patched bytes, what
    (0x09c7234, '88050000', 'ffffffff', 'IOMFB dispatch checkStructureInputSize'),
    (0x15bd404, 'a0008052', '004b8052', 'IOGPU shared-event wait 5 s -> 600 s (mov w0,#600)'),
    (0x15cb320, '083d42b9', '084b8052', 'IOGPUScheduler waitForGPUTimeoutSeconds (1/2): mov w8,#600'),
    (0x15de5bc, '883e42b9', '084b8052', 'IOGPUScheduler waitForGPUTimeoutSeconds (2/2): mov w8,#600'),
    (0x16ae22d, '2016', '801b', 'IOMFB SwapEnd size 0x588 -> 0x6e0'),
    (0x1ab0654, '80f8', 'c4ff', 'container_manager upcall (1/2)'),
    (0x1ab0657, '34', '17', 'container_manager upcall (2/2)'),
    (0x1d43090, '7f2303d5fd7bbfa9', '000080d2c0035fd6', 'task_get_mach_trap_filter_mask -> 0'),
    (0x1d43120, '7f2303d5fd7bbfa9', '000080d2c0035fd6', 'task_get_mach_kobj_filter_mask -> 0'),
    (0x1e0f4e8, 'f60761b2c00e084ee01f803d', '1600b8d23600c0f2fa0761b2', 'shared region size (1/2)'),
    (0x1e0f4f5, '0761b2', '5b07a9', 'shared region size (2/2)'),
    (0x24597b0, 'e01f40f9', 'beffff17', 'IOUC sandbox gate'),
    (0x24ccae8, '7f2303d5f85fbca9', '00008052c0035fd6', 'mac_proc_check_syscall_unix -> 0'),
]


def pick(paths):
    """(path, bytes, sha256) of the first stock or visionOS kernel among paths; exits when none is"""
    seen = []
    for path in paths:
        if not os.path.isfile(path):
            seen.append(f'{path}: not there')
            continue
        k = bytearray(open(path, 'rb').read())
        have = hashlib.sha256(k).hexdigest()
        if have in (STOCK, VISION):
            return path, k, have
        seen.append(f'{path}: SHA-256 {have}')
    sys.exit('no cloudOS 26.4b research kernel (SHA-256 %s) among:\n  %s' % (STOCK, '\n  '.join(seen)))


args = sys.argv[1:]
if len(args) >= 2 and args[0] == '--check':
    path, _, have = pick(args[1:])
    print(f'{path}: {"the visionOS kernel" if have == VISION else "the stock research kernel"}')
    sys.exit(0)
if len(args) < 2:
    sys.exit(__doc__)
dst, src = args[0], args[1:]
src, k, have = pick(src)
if have == VISION:
    print(f'{src} is the visionOS kernel already')
else:
    print(f'{src}: the stock research kernel')
    for off, old, new, what in PATCHES:
        old, new = bytes.fromhex(old), bytes.fromhex(new)
        if k[off:off + len(old)] != old:
            sys.exit(f'{off:#x} ({what}): {k[off:off + len(old)].hex()}, not {old.hex()}')
        k[off:off + len(new)] = new
        print(f'{off:#09x} {old.hex()} -> {new.hex()}  {what}')
    have = hashlib.sha256(k).hexdigest()
    if have != VISION:
        sys.exit(f'the result has SHA-256 {have}, not {VISION}')
open(dst, 'wb').write(k)
print(f'wrote {dst} (SHA-256 {VISION[:16]}...)')
