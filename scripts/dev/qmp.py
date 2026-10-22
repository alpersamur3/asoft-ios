#!/usr/bin/env python3
"""Send QMP commands to a QEMU started with qemu-sweet.py --qmp-tcp PORT.
  qmp.py PORT screendump FILE.png      save the current display (ramfb)
  qmp.py PORT hmp 'info cpus'          any human-monitor command
"""
import json, socket, sys


def call(f, sock, name, **args):
    sock.sendall(json.dumps({'execute': name, 'arguments': args}).encode() + b'\n')
    while True:
        r = json.loads(f.readline())
        if 'return' in r or 'error' in r:
            return r


def main():
    port, cmd, arg = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    with socket.create_connection(('127.0.0.1', port), timeout=60) as sock:
        f = sock.makefile('r')
        json.loads(f.readline())                 # greeting
        call(f, sock, 'qmp_capabilities')
        if cmd == 'screendump':
            r = call(f, sock, 'screendump', filename=arg, format='png')
        else:
            r = call(f, sock, 'human-monitor-command', **{'command-line': arg})
        print(r.get('return', r) if not isinstance(r.get('return'), str) else r['return'])


if __name__ == '__main__':
    main()
