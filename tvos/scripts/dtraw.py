"""IM4P -> raw payload (device trees are stored uncompressed), with ios26's mktc.py beside this script (the
install's tvos\\scripts has both).

    dtraw.py IN.im4p OUT.raw
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mktc import im4p_payload  # noqa: E402

b = open(sys.argv[1], 'rb').read()
p = im4p_payload(b)
open(sys.argv[2], 'wb').write(p)
print(len(b), '->', len(p), p[:16])
