#!/usr/bin/env python3
# OpenGL ES for the iOS 26 guest: name a GLES renderer in the paravirtual GPU's personality.
#
# OpenGLES's libGFXShared (gfxInitializeLibrary) reads IOGLESBundleName and IOGLESMetalBundleName
# from each IOAcceleratorES service and loads /System/Library/Extensions/<name>.bundle/<name>; with
# neither, it loads no renderer and every EAGLContext is nil (vphone-cli issue #793). The
# AppleParavirtGPU personality (AppleParavirtGPUIOGPUFamily.kext, "AppleParavirtGPUARM") has only
# MetalPluginName. This adds IOGLESMetalBundleName = AppleMetalGLRenderer (OpenGL ES on Metal, in
# the guest's shared cache) and IOGLESDefaultUseMetal = true to that personality in the
# kernelcache's prelink plist (__PRELINK_INFO,__info), which the kernel parses at boot. The
# plist ends in zero padding before its section does: the rest of the plist moves into that
# padding, and nothing outside the section moves. The kext's _InfoPlistDigest is not checked at
# boot (measured: the patched kernelcache boots).
#   kc-gles.py bootkc out        (out may be bootkc itself; refuses a kernelcache already done)
import struct
import sys

PERSONALITY = b'<key>AppleParavirtGPUARM</key>'
CLASS = b'<string>AppleParavirtGPU</string>'
KEYS = (b'<key>IOGLESMetalBundleName</key>', b'<string>AppleMetalGLRenderer</string>',
        b'<key>IOGLESDefaultUseMetal</key>', b'<true/>')


def prelink_info(kc):
    magic, _, _, _, ncmds, _, _, _ = struct.unpack_from('<IiiIIIII', kc, 0)
    if magic != 0xfeedfacf:
        sys.exit('not a 64-bit Mach-O kernelcache (unwrapped?)')
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', kc, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            nsects = struct.unpack_from('<I', kc, off + 64)[0]
            for j in range(nsects):
                s = off + 72 + 80 * j
                if kc[s:s + 16].rstrip(b'\0') == b'__info' and kc[s + 16:s + 32].rstrip(b'\0') == b'__PRELINK_INFO':
                    _, sz, fo = struct.unpack_from('<QQI', kc, s + 32)
                    return fo, sz
        off += size
    sys.exit('no __PRELINK_INFO,__info section')


def main():
    if len(sys.argv) != 3:
        sys.exit('usage: kc-gles.py bootkc out')
    kc = bytearray(open(sys.argv[1], 'rb').read())
    fo, sz = prelink_info(kc)
    sect = kc[fo:fo + sz]
    end = sect.find(b'\0')
    if end < 0:
        sys.exit('prelink plist is not NUL-terminated')
    p = sect[:end]
    i = p.find(PERSONALITY)
    if i < 0 or p.find(PERSONALITY, i + 1) >= 0:
        sys.exit('want exactly one AppleParavirtGPUARM personality')
    d = p.find(b'<dict>', i)
    close = p.find(b'</dict>', d)
    body = p[d:close]
    if CLASS not in body or b'<dict>' in body[6:]:
        sys.exit('AppleParavirtGPUARM personality is not the expected flat dict with IOClass AppleParavirtGPU')
    if b'IOGLES' in body:
        sys.exit('the personality already names a GLES renderer')
    # the indentation of the personality's last key, for the new ones
    line = p.rfind(b'\n', d, close)
    indent = p[line:close] + b'\t'
    insert = b''.join(indent + k for k in KEYS)
    if end + len(insert) + 1 > sz or any(sect[end:end + len(insert) + 1]):
        sys.exit('no zero padding after the prelink plist for %d more bytes' % len(insert))
    at = fo + line
    kc[at:fo + end + len(insert)] = insert + kc[at:fo + end]
    open(sys.argv[2], 'wb').write(kc)
    print('AppleParavirtGPUARM: +IOGLESMetalBundleName=AppleMetalGLRenderer +IOGLESDefaultUseMetal=true '
          '(%d bytes at file offset 0x%x; plist 0x%x -> 0x%x bytes of 0x%x)' % (len(insert), at, end, end + len(insert), sz))


if __name__ == '__main__':
    main()
