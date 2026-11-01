"""Run commands in the guest's root shell (com.asoft.bash on the serial console, which the
launcher puts on TCP 127.0.0.1:4451) and print what each one printed. Install-iOS26.ps1 uses it
to see that a first start has got far enough and to sync the disk before it quits iOS.

    guest-shell.py PORT WAIT CMD [CMD ...]

Connects (QEMU may not be listening yet) and runs each CMD as
echo @@<tag>"S"@@; CMD; echo @@<tag>"E"@@, so its output is told apart from the console's
echo and the kernel's messages. A command that gets no answer is sent again (with a new tag)
until WAIT seconds have passed, so give it commands that may run twice (test -e, sync, ls).
Exit 0 once every command answered, 1 if one did not in time.
"""
import socket, sys, time


def connect(port, until):
    while True:
        try:
            s = socket.create_connection(('127.0.0.1', port), timeout=5)
            s.settimeout(0.5)
            return s
        except OSError:
            if time.time() > until:
                return None
            time.sleep(2)


def run(s, cmd, until, retry=30):
    buf, n = b'', 0
    while time.time() < until:
        n += 1
        tag = 'G%d%dG' % (int(time.time() * 1000) % 10 ** 9, n)
        s.sendall(('echo @@%s"S"@@; %s; echo @@%s"E"@@\r' % (tag, cmd, tag)).encode())
        start, end = ('@@%sS@@' % tag).encode(), ('@@%sE@@' % tag).encode()
        again = min(until, time.time() + retry)
        while time.time() < again:
            try:
                d = s.recv(65536)
                if not d:
                    raise OSError('the console closed')
                buf += d
            except socket.timeout:
                pass
            i = buf.find(start)
            j = buf.find(end, i + 1) if i >= 0 else -1
            if j > i >= 0:
                return buf[i + len(start):j].decode('utf-8', 'replace').strip('\r\n')
    return None


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    port, wait, cmds = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3:]
    until = time.time() + wait
    s = connect(port, until)
    if s is None:
        print('no console on port %d' % port)
        return 1
    try:
        s.sendall(b'\r')
        for cmd in cmds:
            out = run(s, cmd, until)
            if out is None:
                print('$ %s\n(no answer in %d s)' % (cmd, wait))
                return 1
            print('$ %s\n%s' % (cmd, out), flush=True)
    except OSError as e:
        print('console: %s' % e)
        return 1
    finally:
        s.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
