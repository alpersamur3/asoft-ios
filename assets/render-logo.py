"""Render assets/logo.svg (and logo-small.svg for 32 px and below) to the PNG and ICO
files the app uses: logo-256.png (README, QEMU window icon), logo.ico (shortcut).

  render-logo.py [RSVG_CONVERT]      default: MSYS2's rsvg-convert
Needs Pillow.
"""
import io, os, subprocess, sys
from PIL import Image

here = os.path.dirname(os.path.abspath(__file__))
rsvg = sys.argv[1] if len(sys.argv) > 1 else r'C:\msys64\ucrt64\bin\rsvg-convert.exe'


def render(size):
    svg = 'logo-small.svg' if size <= 32 else 'logo.svg'
    png = subprocess.run([rsvg, '-w', str(size), '-h', str(size), os.path.join(here, svg)],
                         check=True, capture_output=True).stdout
    return Image.open(io.BytesIO(png)).convert('RGBA')


sizes = (16, 24, 32, 48, 64, 128, 256)
images = {s: render(s) for s in sizes}
images[256].save(os.path.join(here, 'logo-256.png'))
render(512).save(os.path.join(here, 'logo-512.png'))
images[256].save(os.path.join(here, 'logo.ico'), format='ICO', sizes=[(s, s) for s in sizes],
                 append_images=[images[s] for s in sizes if s != 256])
print('logo-256.png, logo-512.png, logo.ico')
