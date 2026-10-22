"""Generate the ASoftware iOS logo: an iPhone in front of a PC monitor, with depth.

  make-logo.py OUT.svg [--small]     --small: fewer details, for 16-32 px

assets/logo.svg and logo-small.svg come from it; render-logo.py makes the PNG and ICO files.
"""
import sys

small = '--small' in sys.argv
out = sys.argv[1]
p = []
add = p.append

add('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">')
add('<title>ASoftware iOS</title>')
add('''<defs>
  <linearGradient id="bezel" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#3a4054"/><stop offset="1" stop-color="#191c27"/>
  </linearGradient>
  <linearGradient id="desk" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#1aa7b8"/><stop offset="0.55" stop-color="#155e8a"/><stop offset="1" stop-color="#1b2a63"/>
  </linearGradient>
  <radialGradient id="bloom" cx="0.32" cy="0.38" r="0.55">
    <stop offset="0" stop-color="#7ef0e4" stop-opacity="0.55"/><stop offset="1" stop-color="#7ef0e4" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="neck" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#2c3243"/><stop offset="0.5" stop-color="#3d4458"/><stop offset="1" stop-color="#1d212d"/>
  </linearGradient>
  <linearGradient id="base" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#4a5167"/><stop offset="1" stop-color="#1f2330"/>
  </linearGradient>
  <linearGradient id="frame" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#8a909d"/><stop offset="0.12" stop-color="#3a3f4b"/>
    <stop offset="0.88" stop-color="#2a2e38"/><stop offset="1" stop-color="#737986"/>
  </linearGradient>
  <linearGradient id="wall" x1="0" y1="0" x2="0.35" y2="1">
    <stop offset="0" stop-color="#5a9bff"/><stop offset="0.6" stop-color="#4a5df0"/><stop offset="1" stop-color="#5b36cf"/>
  </linearGradient>
  <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#ffffff" stop-opacity="0.32"/><stop offset="0.55" stop-color="#ffffff" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="glass" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#ffffff" stop-opacity="0.22"/><stop offset="0.45" stop-color="#ffffff" stop-opacity="0.05"/>
    <stop offset="0.46" stop-color="#ffffff" stop-opacity="0"/>
  </linearGradient>
  <filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="9"/></filter>
  <filter id="softer" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="4"/></filter>
  <clipPath id="screen"><rect x="40" y="78" width="352" height="222" rx="10"/></clipPath>
  <clipPath id="phone-screen"><rect x="291" y="155" width="158" height="312" rx="27"/></clipPath>
</defs>''')

# Contact shadows on the "desk"
add('<ellipse cx="214" cy="420" rx="118" ry="12" fill="#0b0d14" opacity="0.28" filter="url(#soft)"/>')
add('<ellipse cx="370" cy="488" rx="92" ry="10" fill="#0b0d14" opacity="0.35" filter="url(#soft)"/>')

# Monitor: stand, base, body, screen
add('<path d="M190 330 h48 l13 58 h-74 z" fill="url(#neck)"/>')
add('<rect x="132" y="384" width="164" height="26" rx="13" fill="url(#base)"/>')
add('<path d="M145 386.5 h138" stroke="#ffffff" stroke-opacity="0.25" stroke-width="2" stroke-linecap="round"/>')
add('<rect x="20" y="58" width="392" height="274" rx="24" fill="url(#bezel)"/>')
add('<path d="M44 59.5 h344" stroke="#ffffff" stroke-opacity="0.22" stroke-width="2" stroke-linecap="round"/>')
add('<rect x="40" y="78" width="352" height="222" rx="10" fill="url(#desk)"/>')
add('<g clip-path="url(#screen)">')
add('<rect x="40" y="78" width="352" height="222" fill="url(#bloom)"/>')
if not small:
    # a window on the desktop, and the taskbar
    add('<rect x="66" y="104" width="150" height="104" rx="8" fill="#0f172a" fill-opacity="0.45"/>')
    add('<rect x="66" y="104" width="150" height="18" rx="8" fill="#0f172a" fill-opacity="0.35"/>')
    add('<rect x="40" y="276" width="352" height="24" fill="#0b1224" fill-opacity="0.72"/>')
    for i, c in enumerate(('#5ac8fa', '#ffd60a', '#34c759', '#ff9f0a', '#e5e7eb')):
        add(f'<rect x="{171 + i * 19}" y="282" width="13" height="13" rx="3.5" fill="{c}"/>')
add('<polygon points="40,78 250,78 120,300 40,300" fill="#ffffff" opacity="0.06"/>')
add('</g>')

# iPhone: shadow cast onto the monitor, metal frame, side buttons, bezel, screen
add('<rect x="268" y="152" width="190" height="334" rx="40" fill="#05060a" opacity="0.45" filter="url(#softer)"/>')
add('<rect x="274" y="246" width="5" height="30" rx="2" fill="#4b505c"/>')
add('<rect x="274" y="284" width="5" height="30" rx="2" fill="#4b505c"/>')
add('<rect x="465" y="262" width="5" height="48" rx="2" fill="#4b505c"/>')
add('<rect x="277" y="140" width="190" height="340" rx="42" fill="url(#frame)"/>')
add('<rect x="282" y="145" width="180" height="330" rx="37" fill="#0a0c11"/>')
add('<rect x="291" y="155" width="158" height="312" rx="27" fill="url(#wall)"/>')
add('<g clip-path="url(#phone-screen)">')
add('<path d="M339 155 H401 V162 a10 10 0 0 1 -10 10 H349 a10 10 0 0 1 -10 -10 Z" fill="#0a0c11"/>')

def tile(x, y, s, color):
    r = s * 0.27
    add(f'<rect x="{x}" y="{y + 1.5}" width="{s}" height="{s}" rx="{r}" fill="#000000" opacity="0.18"/>')
    add(f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{r}" fill="{color}"/>')
    add(f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{r}" fill="url(#tile)"/>')

colors = ['#34c759', '#f2f2f7', '#ff9f0a', '#ff453a', '#64d2ff', '#ffd60a', '#bf5af2', '#0a84ff', '#30d158']
if small:
    for i, c in enumerate(colors[:4]):
        tile(307 + (i % 2) * 70, 196 + (i // 2) * 70, 56, c)
else:
    for i, c in enumerate(colors):
        tile(307 + (i % 3) * 46, 192 + (i // 3) * 50, 34, c)
    # dock with three apps, home indicator
    add('<rect x="301" y="396" width="138" height="52" rx="17" fill="#ffffff" fill-opacity="0.26"/>')
    for i, c in enumerate(('#34c759', '#f2f2f7', '#30d158')):
        tile(316 + i * 40, 405, 32, c)
    add('<rect x="345" y="456" width="50" height="5" rx="2.5" fill="#ffffff"/>')
# glass sheen
add('<rect x="291" y="155" width="158" height="312" fill="url(#glass)"/>')
add('</g>')
add('<rect x="277.75" y="140.75" width="188.5" height="338.5" rx="41.25" fill="none" stroke="#ffffff" stroke-opacity="0.28" stroke-width="1.5"/>')
add('</svg>')

with open(out, 'w', encoding='utf-8', newline='\n') as f:
    f.write('\n'.join(p) + '\n')
print('wrote', out)
