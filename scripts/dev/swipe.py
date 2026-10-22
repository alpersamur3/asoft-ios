#!/usr/bin/env python3
"""Drive the virtio tablet (= iOS touchscreen) through QMP input-send-event.

  swipe.py PORT X0 Y0 X1 Y1 [STEPS] [SECONDS]    fractions of the screen, e.g. 0.5 0.99 0.5 0.35
  swipe.py PORT tap X Y
  swipe.py PORT unlock                            fast full-height flick from the bottom edge

The lock screen only unlocks on a quick, long flick (it springs back after a slow
or short drag); inside apps a slower bottom-edge swipe goes home.
"""
import json, socket, sys, time

port = int(sys.argv[1])
sock = socket.create_connection(('127.0.0.1', port), timeout=30)
f = sock.makefile('r')
json.loads(f.readline())


def call(name, **args):
    sock.sendall(json.dumps({'execute': name, 'arguments': args}).encode() + b'\n')
    while True:
        r = json.loads(f.readline())
        if 'return' in r or 'error' in r:
            if 'error' in r:
                raise SystemExit(r['error'])
            return r['return']


def abs_events(x, y):
    return [{'type': 'abs', 'data': {'axis': 'x', 'value': int(x * 32767)}},
            {'type': 'abs', 'data': {'axis': 'y', 'value': int(y * 32767)}}]


def btn(down):
    return {'type': 'btn', 'data': {'down': down, 'button': 'left'}}


call('qmp_capabilities')
if sys.argv[2] == 'unlock':
    sys.argv[2:] = ['0.5', '0.997', '0.5', '0.08', '15', '0.3']
if sys.argv[2] == 'tap':
    x, y = float(sys.argv[3]), float(sys.argv[4])
    call('input-send-event', events=abs_events(x, y) + [btn(True)])
    time.sleep(0.15)
    call('input-send-event', events=[btn(False)])
else:
    x0, y0, x1, y1 = map(float, sys.argv[2:6])
    steps = int(sys.argv[6]) if len(sys.argv) > 6 else 12
    secs = float(sys.argv[7]) if len(sys.argv) > 7 else 0.4
    call('input-send-event', events=abs_events(x0, y0) + [btn(True)])
    for i in range(1, steps + 1):
        time.sleep(secs / steps)
        t = i / steps
        call('input-send-event', events=abs_events(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    time.sleep(0.05)
    call('input-send-event', events=[btn(False)])
print('ok')
