"""The watchOS kernelcache: cloudOS 26.4b's research kernel (the iOS 26 install's plain kernel, decompressed,
unpatched) with the iOS 27 userland's patches and one of the watch's own, each checked against the stock
bytes first and the result against its SHA-256. A file other than that kernel is refused.

  iOS 27 (vphone-cli's research names; offsets in this kernelcache):
  - IOMobileFramebuffer user client: its dispatch table's checkStructureInputSize 0x588 -> any, and
    SwapEnd's cmp w2,#0x588 -> #0x6e0 (27.x sends 0x6e0 bytes), so its swaps reach the paravirtual scanout
  - kernel-boot-container_manager_upcall (JB-02d): the cbz after the upcall becomes a b to success
  - kernel-boot-shared_region_size: the arm64 shared region 0x1C0000000 at 0x180000000, for 27.x's cache
  - kernel-boot-iouc_sandbox_gate (JB-10b): "IOUC %s failed sandbox" goes to the allow path
  watchOS:
  - Sandbox's mpo_proc_check_syscall_unix hook answers 0 (mov w0,#0; retab): Foundation's atomic write on
    HFS+ falls back to renameat (syscall 465), which identityservicesd's and sharingd's profiles deny
    (SIGKILL namespace SANDBOX 221 on every boot); file rules still apply through the vnode hooks.

    kc-watch.py OUT IN [IN ...]     the first IN that is the stock (or the watch) kernel, patched into OUT
    kc-watch.py --check IN [IN ...]  only names it (exit 1 when none is)

The iOS 26 install has the stock kernel as cloud/kernelcache.research.vphone600.decompressed; its fw/bootkc
is that file too, unless its gpu step (GpuMode cloudos with the release's compiler plugin) rewrote it with
kc-gles.py (OpenGL ES's personality keys in the prelink plist), which this refuses.
"""
import hashlib, os, sys

STOCK = '86895a2eebeb7fcfb68bcd60f2d7e685687faea07ee31166fb58c872b38e0d92'
WATCH = '4f2301891bc574f50b10da2cbb4dd2b30806bcda230ea85192b7a7569bfbca1c'
PATCHES = [   # file offset, stock bytes, patched bytes, what
    (0x09c7234, '88050000', 'ffffffff', 'IOMFB dispatch checkStructureInputSize'),
    (0x16ae22d, '2016', '801b', 'IOMFB SwapEnd size 0x588 -> 0x6e0'),
    (0x1a9b86c, 'f44fbea9fd7b01a9', '00008052ff0f5fd6', 'Sandbox mpo_proc_check_syscall_unix -> 0'),
    (0x1ab0654, '80f8', 'c4ff', 'container_manager upcall (1/2)'),
    (0x1ab0657, '34', '17', 'container_manager upcall (2/2)'),
    (0x1e0f4e8, 'f60761b2c00e084ee01f803d', '1600b8d23600c0f2fa0761b2', 'shared region size (1/2)'),
    (0x1e0f4f5, '0761b2', '5b07a9', 'shared region size (2/2)'),
    (0x24597b0, 'e01f40f9', 'beffff17', 'IOUC sandbox gate'),
]

def pick(paths):
    """(path, bytes, sha256) of the first stock or watch kernel among paths; exits when none is"""
    seen = []
    for path in paths:
        if not os.path.isfile(path):
            seen.append(f'{path}: not there')
            continue
        k = bytearray(open(path, 'rb').read())
        have = hashlib.sha256(k).hexdigest()
        if have in (STOCK, WATCH):
            return path, k, have
        seen.append(f'{path}: SHA-256 {have}')
    sys.exit('no cloudOS 26.4b research kernel (SHA-256 %s) among:\n  %s' % (STOCK, '\n  '.join(seen)))


args = sys.argv[1:]
if len(args) >= 2 and args[0] == '--check':
    path, _, have = pick(args[1:])
    print(f'{path}: {"the watch kernel" if have == WATCH else "the stock research kernel"}')
    sys.exit(0)
if len(args) < 2:
    sys.exit(__doc__)
dst, src = args[0], args[1:]
src, k, have = pick(src)
if have == WATCH:
    print(f'{src} is the watch kernel already')
else:
    print(f'{src}: the stock research kernel')
    for off, old, new, what in PATCHES:
        old, new = bytes.fromhex(old), bytes.fromhex(new)
        if k[off:off + len(old)] != old:
            sys.exit(f'{off:#x} ({what}): {k[off:off + len(old)].hex()}, not {old.hex()}')
        k[off:off + len(new)] = new
        print(f'{off:#09x} {old.hex()} -> {new.hex()}  {what}')
    have = hashlib.sha256(k).hexdigest()
    if have != WATCH:
        sys.exit(f'the result has SHA-256 {have}, not {WATCH}')
open(dst, 'wb').write(k)
print(f'wrote {dst} (SHA-256 {WATCH[:16]}...)')
