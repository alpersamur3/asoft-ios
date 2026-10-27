"""Inject input into the running QEMU over QMP (port 4453). Pixel coords on the
1179x2556 display, scaled to the 0-32767 abs range.
  qmp.py tap PX PY
  qmp.py swipe PX1 PY1 PX2 PY2 [steps] [ms]
  qmp.py key KEYNAME            (QMP qcode, e.g. ret, 1, 2, home)
  qmp.py info                   (query input devices)
"""
import socket, json, sys, time
W, H = 1179, 2556
def sx(px): return max(0, min(32767, int(px / W * 32767)))
def sy(py): return max(0, min(32767, int(py / H * 32767)))
s = socket.create_connection(('127.0.0.1', 4453), timeout=10)
f = s.makefile('rwb')
def recv():
    while True:
        line = f.readline()
        if not line: raise SystemExit('qmp closed')
        o = json.loads(line)
        if 'event' in o: continue
        return o
recv()  # greeting
def cmd(c):
    f.write((json.dumps(c) + '\n').encode()); f.flush()
    return recv()
cmd({"execute": "qmp_capabilities"})
def send(events):
    r = cmd({"execute": "input-send-event", "arguments": {"events": events}})
    if 'error' in r: print('ERR', r['error'])
    return r
def moveabs(px, py):
    send([{"type": "abs", "data": {"axis": "x", "value": sx(px)}},
          {"type": "abs", "data": {"axis": "y", "value": sy(py)}}])
a = sys.argv[1]
if a == 'tap':
    px, py = float(sys.argv[2]), float(sys.argv[3])
    moveabs(px, py)
    send([{"type": "btn", "data": {"button": "left", "down": True}}])
    time.sleep(0.08)
    send([{"type": "btn", "data": {"button": "left", "down": False}}])
    print("tap", px, py)
elif a == 'swipe':
    x1, y1, x2, y2 = map(float, sys.argv[2:6])
    steps = int(sys.argv[6]) if len(sys.argv) > 6 else 20
    ms = int(sys.argv[7]) if len(sys.argv) > 7 else 400
    moveabs(x1, y1)
    send([{"type": "btn", "data": {"button": "left", "down": True}}])
    for i in range(1, steps + 1):
        moveabs(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
        time.sleep(ms / 1000.0 / steps)
    send([{"type": "btn", "data": {"button": "left", "down": False}}])
    print("swipe", x1, y1, "->", x2, y2)
elif a == 'key':
    send([{"type": "key", "data": {"down": True, "key": {"type": "qcode", "data": sys.argv[2]}}}])
    time.sleep(0.05)
    send([{"type": "key", "data": {"down": False, "key": {"type": "qcode", "data": sys.argv[2]}}}])
    print("key", sys.argv[2])
elif a == 'info':
    print(json.dumps(cmd({"execute": "query-mice"}), indent=1))
