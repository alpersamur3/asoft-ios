#!/usr/bin/env python3
"""Decode a QEMU `screendump` PPM correctly.

QEMU's ppm_save (ui/ui-qmp-cmds.c, 11.1.0 lines 309-314) writes each row with
pixman_image_get_stride(linebuf) bytes, i.e. width*3 rounded UP to a multiple
of 4, while the header says the true width. For 1179 px rows that is 3540
bytes instead of 3537: every header-trusting reader (PIL, ImageMagick, ...)
starts each row 3 bytes (1 px) early and shows the frame sheared by +1 px/row,
wrapping at row 1179. This reader uses the padded stride when the file size
says so, then drops the padding.

usage: ppmfix.py IN.ppm [OUT.png]        (OUT defaults to IN with .png)
       ppmfix.py --check IN.ppm ...      (only report tight/padded, no output)
"""
import re
import sys
import numpy as np
from PIL import Image


def load(path):
    raw = open(path, 'rb').read()
    m = re.match(rb'P6\s+(\d+)\s+(\d+)\s+(\d+)\s', raw)
    if not m:
        raise SystemExit(f"{path}: not a binary PPM")
    w, h = int(m.group(1)), int(m.group(2))
    data = raw[m.end():]
    tight, padded = w * 3, (w * 3 + 3) // 4 * 4
    if len(data) >= padded * h and padded != tight:
        stride, kind = padded, 'padded'
    else:
        stride, kind = tight, 'tight'
    a = np.frombuffer(data, dtype=np.uint8)[:stride * h].reshape(h, stride)[:, :tight]
    return Image.fromarray(a.reshape(h, w, 3).copy(), 'RGB'), kind, stride


def main(argv):
    if not argv:
        raise SystemExit(__doc__)
    if argv[0] == '--check':
        for p in argv[1:]:
            im, kind, stride = load(p)
            print(f"{p}: {im.size[0]}x{im.size[1]} rows {kind} ({stride} bytes)")
        return
    src = argv[0]
    out = argv[1] if len(argv) > 1 else re.sub(r'\.ppm$', '', src) + '.png'
    im, kind, stride = load(src)
    im.save(out)
    print(f"{src}: {im.size[0]}x{im.size[1]}, rows {kind} ({stride} bytes) -> {out}")


if __name__ == '__main__':
    main(sys.argv[1:])
