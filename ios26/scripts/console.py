"""Drive the guest console over a QEMU socket chardev.

    console.py PORT LOGFILE WAIT_SECONDS [COMMAND ...]

Waits (up to WAIT_SECONDS) for a shell prompt in LOGFILE, sends each COMMAND
followed by Enter, waits for the next prompt, and prints what came back.
"""
import re, socket, sys, time

port, log, wait = int(sys.argv[1]), sys.argv[2], float(sys.argv[3])
cmds = []
for a in sys.argv[4:]:		# @FILE: one command per line
    if a.startswith('@'):
        cmds += [l.rstrip('\r\n') for l in open(a[1:]) if l.strip()]
    else:
        cmds.append(a)
PROMPT = re.compile(rb'[a-z]+-[0-9.]+[#$]$')		# bash-5.2#, sh-5.2$

s = socket.create_connection(('127.0.0.1', port), timeout=5)
s.settimeout(0.5)
buf = b''


def pump(seconds, until=None):
    global buf
    end = time.time() + seconds
    while time.time() < end:
        try:
            d = s.recv(65536)
            if d:
                buf += d
        except socket.timeout:
            pass
        if until is not None and until.search(buf.rstrip()):
            return True
    return False


t0 = time.time()
found = pump(wait, PROMPT)
if not found:			# connected after the prompt was printed: ask again
    s.sendall(b'\r')
    found = pump(10, PROMPT)
print(f'--- prompt {"seen" if found else "NOT seen"} after {time.time() - t0:.0f}s')
tail = buf[-1500:].decode(errors='replace')
print(tail)
if not found:
    sys.exit(1)
for c in cmds:
    buf = b''
    s.sendall(c.encode() + b'\r')
    pump(60, PROMPT)
    print(f'--- {c}')
    print(buf.decode(errors='replace'))
