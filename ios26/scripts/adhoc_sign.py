"""Ad-hoc sign a thin 64-bit Mach-O in place, like `codesign -s - -i ID FILE`.

    adhoc_sign.py FILE [ID]

Prints the CDHash (for a trust cache). An existing signature is replaced.
CodeDirectory 0x20400, SHA-256, 4 KB pages, empty requirements, no
entitlements, empty CMS slot (as codesign does for ad-hoc signatures).
"""
import hashlib, os, struct, sys

LC_SEGMENT_64, LC_CODE_SIGNATURE = 0x19, 0x1d
MH_EXECUTE = 2
CSMAGIC_REQUIREMENTS, CSMAGIC_CODEDIRECTORY = 0xfade0c01, 0xfade0c02
CSMAGIC_EMBEDDED_SIGNATURE, CSMAGIC_BLOBWRAPPER = 0xfade0cc0, 0xfade0b01
CSSLOT_CODEDIRECTORY, CSSLOT_REQUIREMENTS, CSSLOT_SIGNATURESLOT = 0, 2, 0x10000
CS_ADHOC, CS_EXECSEG_MAIN_BINARY = 0x2, 0x1
PAGE = 4096
CD_HEADER = 88                  # through execSegFlags (version 0x20400)
N_SPECIAL = 2                   # -1 Info.plist (none), -2 requirements


def align(x, a):
    return (x + a - 1) // a * a


def sign(path, ident):
    buf = bytearray(open(path, 'rb').read())
    magic, cpu, sub, ftype, ncmds, sizeofcmds = struct.unpack_from('<IiiIII', buf)
    if magic != 0xfeedfacf:
        raise SystemExit(f'{path}: not a thin 64-bit Mach-O')

    off, linkedit, text, sigcmd, first_data = 32, None, None, None, len(buf)
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', buf, off)
        if cmd == LC_SEGMENT_64:
            name = bytes(buf[off + 8:off + 24]).split(b'\0')[0]
            fileoff, filesize = struct.unpack_from('<QQ', buf, off + 40)
            nsects, = struct.unpack_from('<I', buf, off + 64)
            if name == b'__LINKEDIT':
                linkedit = off
            elif name == b'__TEXT':
                text = (fileoff, filesize)
            for i in range(nsects):
                soff, = struct.unpack_from('<I', buf, off + 72 + 80 * i + 48)
                if soff:
                    first_data = min(first_data, soff)
        elif cmd == LC_CODE_SIGNATURE:
            sigcmd = off
        off += size
    if linkedit is None or text is None:
        raise SystemExit(f'{path}: no __LINKEDIT/__TEXT')

    if sigcmd is not None:		# drop the old signature, reuse its load command
        dataoff, = struct.unpack_from('<I', buf, sigcmd + 8)
        del buf[dataoff:]
    else:
        if 32 + sizeofcmds + 16 > first_data:
            raise SystemExit(f'{path}: no room for LC_CODE_SIGNATURE')
        sigcmd = 32 + sizeofcmds
        struct.pack_into('<II', buf, 16, ncmds + 1, sizeofcmds + 16)

    code_limit = align(len(buf), 16)
    buf += bytes(code_limit - len(buf))
    nslots = (code_limit + PAGE - 1) // PAGE
    ident_b = ident.encode() + b'\0'
    hash_off = CD_HEADER + len(ident_b) + 32 * N_SPECIAL
    cd_len = hash_off + 32 * nslots
    req = struct.pack('>III', CSMAGIC_REQUIREMENTS, 12, 0)
    cms = struct.pack('>II', CSMAGIC_BLOBWRAPPER, 8)
    nblobs = 3
    sb_hdr = 12 + 8 * nblobs
    sb_len = sb_hdr + cd_len + len(req) + len(cms)
    datasize = align(sb_len, 16)

    # load commands first: they are inside the hashed pages
    struct.pack_into('<IIII', buf, sigcmd, LC_CODE_SIGNATURE, 16, code_limit, datasize)
    le_fileoff, = struct.unpack_from('<Q', buf, linkedit + 40)
    le_filesize = code_limit + datasize - le_fileoff
    struct.pack_into('<QQ', buf, linkedit + 32, align(le_filesize, 0x4000), le_fileoff)
    struct.pack_into('<Q', buf, linkedit + 48, le_filesize)

    slots = b''.join(hashlib.sha256(bytes(buf[i * PAGE:min((i + 1) * PAGE, code_limit)])).digest()
                     for i in range(nslots))
    special = hashlib.sha256(req).digest() + bytes(32)		# slot -2, slot -1
    exec_flags = CS_EXECSEG_MAIN_BINARY if ftype == MH_EXECUTE else 0
    cd = struct.pack('>IIIIIIIII', CSMAGIC_CODEDIRECTORY, cd_len, 0x20400, CS_ADHOC,
                     hash_off, CD_HEADER, N_SPECIAL, nslots, code_limit)
    cd += struct.pack('>BBBBI', 32, 2, 0, 12, 0)		# hashSize, SHA-256, platform, 4K pages
    cd += struct.pack('>IIIQ', 0, 0, 0, 0)			# scatter, team, spare3, codeLimit64
    cd += struct.pack('>QQQ', text[0], text[1], exec_flags)
    assert len(cd) == CD_HEADER
    cd += ident_b + special + slots
    assert len(cd) == cd_len

    sb = struct.pack('>III', CSMAGIC_EMBEDDED_SIGNATURE, sb_len, nblobs)
    sb += struct.pack('>II', CSSLOT_CODEDIRECTORY, sb_hdr)
    sb += struct.pack('>II', CSSLOT_REQUIREMENTS, sb_hdr + cd_len)
    sb += struct.pack('>II', CSSLOT_SIGNATURESLOT, sb_hdr + cd_len + len(req))
    sb += cd + req + cms
    buf += sb + bytes(datasize - len(sb))

    mode = os.stat(path).st_mode
    open(path, 'wb').write(buf)
    os.chmod(path, mode)
    return hashlib.sha256(cd).hexdigest()[:40]


if __name__ == '__main__':
    path = sys.argv[1]
    ident = sys.argv[2] if len(sys.argv) > 2 else os.path.basename(path)
    print(sign(path, ident), path)
