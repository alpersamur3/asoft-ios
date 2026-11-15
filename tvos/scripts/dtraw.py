"""IM4P -> raw payload, with ios26's mktc.py and tools' lzfse.py beside this script (the install's tvos\\scripts
has them). A payload stored LZFSE-compressed ("bvx2": tvOS 27.2's J255 device tree is 30,624 bytes that unpack to
170,380) is unpacked; one stored plain is written as it is.

    dtraw.py IN.im4p OUT.raw
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mktc import im4p_payload  # noqa: E402

b = open(sys.argv[1], 'rb').read()
p = im4p_payload(b)
packed = len(p)
if p[:3] == b'bvx':
    import lzfse  # noqa: E402
    p = lzfse.decompress(p)
open(sys.argv[2], 'wb').write(p)
print(len(b), '->', packed, '->' if len(p) != packed else '=', len(p), p[:16])
