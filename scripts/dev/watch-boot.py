#!/usr/bin/env python3
"""Watch a running qemu-sweet.py --display boot until the screen leaves the Apple logo.

  watch-boot.py QMP_PORT RUN_DIR START_EPOCH [INTERVAL_S]

Every INTERVAL_S (default 30) it grabs the display through QMP (ppm), measures
how much of it is non-black, and reads the disk counters. It prints one line
when the screen changes (saving RUN_DIR/screen-<uptime>s.png), a heartbeat every
5 minutes, and a final line if QEMU goes away or the kernel log shows a panic.
"""
import json, os, re, socket, sys, time

port, run_dir, start = int(sys.argv[1]), sys.argv[2], float(sys.argv[3])
interval = float(sys.argv[4]) if len(sys.argv) > 4 else 30.0
serial = os.path.join(run_dir, 'run', 'serial.txt')


def qmp(*cmds):
    with socket.create_connection(('127.0.0.1', port), timeout=60) as sock:
        f = sock.makefile('r')
        json.loads(f.readline())
        out = []
        for name, args in (('qmp_capabilities', {}),) + cmds:
            sock.sendall(json.dumps({'execute': name, 'arguments': args}).encode() + b'\n')
            while True:
                r = json.loads(f.readline())
                if 'return' in r or 'error' in r:
                    out.append(r.get('return', r))
                    break
        return out[1:]


def screen_stats(path):
    """Fraction of non-black pixels and mean brightness, sampling every 8th pixel of a P6 ppm."""
    data = open(path, 'rb').read()
    m = re.match(rb'P6\s+(\d+)\s+(\d+)\s+255\s', data)
    w, h = int(m.group(1)), int(m.group(2))
    px = data[m.end():]
    lit = total = bright = 0
    for i in range(0, w * h * 3, 24):
        s = px[i] + px[i + 1] + px[i + 2]
        bright += s
        lit += s > 60
        total += 1
    return lit / total, bright / total / 3


def disk_reads():
    text = qmp(('human-monitor-command', {'command-line': 'info blockstats'}))[0]
    m = re.search(r'root:.*?Read:\s+(\d+)\s+(\d+)', text, re.S)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def say(msg):
    print(f'[{time.strftime("%H:%M:%S")} t={int(time.time() - start)}s] {msg}', flush=True)


ppm = os.path.join(run_dir, 'watch.ppm')
baseline = None
last_beat = 0
panic_seen = False
while True:
    try:
        qmp(('screendump', {'filename': ppm, 'format': 'ppm'}))
        lit, bright = screen_stats(ppm)
        rbytes, rops = disk_reads()
    except OSError as e:
        say(f'QEMU unreachable ({e}); stopping')
        break
    up = int(time.time() - start)
    if baseline is None:
        baseline = (lit, bright)
        say(f'baseline screen: lit {lit:.4f} brightness {bright:.1f}')
    elif abs(lit - baseline[0]) > max(0.005, baseline[0] / 2) or abs(bright - baseline[1]) > 1.5:
        png = os.path.join(run_dir, f'screen-{up}s.png')
        qmp(('screendump', {'filename': png, 'format': 'png'}))
        say(f'SCREEN CHANGED: lit {lit:.4f} brightness {bright:.1f} -> {png}')
        baseline = (lit, bright)
    if time.time() - last_beat >= 300:
        size = os.path.getsize(serial) if os.path.exists(serial) else 0
        say(f'heartbeat: lit {lit:.4f}, serial {size // 1024} KiB, disk reads {rops} ops / {rbytes >> 20} MiB')
        last_beat = time.time()
    if not panic_seen and os.path.exists(serial):
        with open(serial, 'rb') as f:
            if b'panic(' in f.read():
                panic_seen = True
                say('PANIC in kernel log')
    time.sleep(interval)
