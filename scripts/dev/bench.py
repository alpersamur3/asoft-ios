#!/usr/bin/env python3
"""Boot iOS in QEMU and time the user-visible milestones, for before/after comparisons.

  py -3.12 scripts/dev/bench.py --tag NAME [--cpus 4] [--display gtk|none|gtk,gl=on] [--qemu EXE]
        [--disk-cache writeback] [--disk-aio threads] [--kernel PATH] [--boot-args "..."]

Milestones (seconds since QEMU start):
  display_on   backboardd turns the display on (kernel log)
  lockscreen   lock screen visible (red date/clock pixels on screen)
  home         home screen after F1 (white widgets, lit > 15 %)
  settings     Settings open after tapping its icon (screen mostly light)
  back_home    home screen again after F1
Also records QEMU's busiest-thread share (the main loop) and virtio-blk statistics.
The kernel log has no clock: run\\serial-ts.txt is the same log with the second each line
arrived (host clock, same origin as the milestones). Boot-arg sweettop=MS (kernel 0092+)
adds per-process CPU tables for scripts/dev/boot-profile.py.
Results go to <work>\\bench\\<tag>-<time>\\result.json and one summary line.
Guest writes are discarded (QEMU snapshot), so every run starts from the same disk, unless
--keep-writes (then pass a throwaway overlay as --disk).
"""
import argparse, bisect, json, os, re, socket, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
# what is not in the repo (QEMU, iOS disks, runs): ASOFT_WORK, default work\ in the repo
WORK = os.environ.get('ASOFT_WORK') or os.path.join(REPO, 'work')
# v3: the layer new user disks start from (run-windows.ps1): base image, LaunchServices database
# rebuilt by kernel 0099+ (wallpaper, widgets), asoftinstalld
DISK = os.path.join(WORK, 'root', 'ios16-root-20H392-v3.qcow2')
BOOT_ARGS = ('debug=0xc serial=3 cpus={cpus} keepsyms=1 -enable_kprintf_spam -noprogress rd=vblkroot0 vblkrw=1 '
             'rootrw=1 unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin '
             'launchd_unsecure_cache=1 wdt=-1 sweetfb_hz=30 sweetfb_noconsole=1 sweetfb_keepon=1 '
             'launchd_disable_all_timeouts=1')
SETTINGS_ICON = (0.621, 0.356)
SAFARI_ICON = (0.5, 0.936)          # in the dock
SAFARI_ADDRESS = (0.5, 0.879)       # "Search or enter website name" (bottom bar)
QCODES = {'.': 'dot', '/': 'slash', '-': 'minus', ':': 'shift-semicolon'}
QEMU = os.path.join(WORK, 'qemu', 'v11.1.2-asoft', 'qemu-system-aarch64.exe')


class QMP:
    def __init__(self, port, deadline):
        while True:
            try:
                self.sock = socket.create_connection(('127.0.0.1', port), timeout=120)
                break
            except OSError:
                if time.time() > deadline:
                    raise
                time.sleep(0.5)
        self.f = self.sock.makefile('r')
        json.loads(self.f.readline())
        self.call('qmp_capabilities')

    def call(self, name, **args):
        self.sock.sendall(json.dumps({'execute': name, 'arguments': args}).encode() + b'\n')
        while True:
            r = json.loads(self.f.readline())
            if 'return' in r or 'error' in r:
                return r.get('return', r)

    def hmp(self, cmd):
        return self.call('human-monitor-command', **{'command-line': cmd})


def screen(qmp, path):
    """(lit fraction, red-text fraction, brightness samples) of the display, sampling every 8th pixel."""
    qmp.call('screendump', filename=path, format='ppm')
    data = open(path, 'rb').read()
    m = re.match(rb'P6\s+(\d+)\s+(\d+)\s+255\s', data)
    px = data[m.end():]
    lit = red = 0
    vals = []
    for i in range(0, int(m.group(1)) * int(m.group(2)) * 3, 24):
        r, g, b = px[i], px[i + 1], px[i + 2]
        lit += r + g + b > 300
        # The lock screen's red date/clock, also when iOS has dimmed it (auto-lock: ~(28,2,2))
        red += r >= 20 and r > 2.5 * max(g, b)
        vals.append(r + g + b)
    return lit / len(vals), red / len(vals), vals


def changed(a, b):
    """Fraction of samples whose brightness differs clearly between two screen() samples."""
    return sum(abs(x - y) > 90 for x, y in zip(a, b)) / max(len(a), 1)


def watch_size(path, t0, stop, sizes):
    """Append (seconds since t0, size) whenever the serial log grows, checking every 0.1 s."""
    last = -1
    while not stop.is_set():
        try:
            size = os.path.getsize(path)
        except OSError:
            size = -1
        if size > last:
            sizes.append((round(time.time() - t0, 2), size))
            last = size
        stop.wait(0.1)


def timestamp_lines(path, sizes, dest):
    """Write the serial log with the arrival second of each line in front of it."""
    data = open(path, 'rb').read()
    ends = [s for _, s in sizes]
    with open(dest, 'w', encoding='latin-1', newline='\n') as f:
        pos = 0
        for line in data.rstrip(b'\n').split(b'\n'):
            pos += len(line) + 1
            i = min(bisect.bisect_left(ends, min(pos, len(data))), len(sizes) - 1)
            text = line.rstrip(b'\r').decode('latin-1')
            f.write(f'{sizes[i][0]:8.2f} {text}\n')


def tap(qmp, x, y):
    """A 150 ms touch at (x, y), fractions of the screen."""
    qmp.call('input-send-event', events=[{'type': 'abs', 'data': {'axis': 'x', 'value': int(x * 32767)}},
                                         {'type': 'abs', 'data': {'axis': 'y', 'value': int(y * 32767)}},
                                         {'type': 'btn', 'data': {'down': True, 'button': 'left'}}])
    time.sleep(0.15)
    qmp.call('input-send-event', events=[{'type': 'btn', 'data': {'down': False, 'button': 'left'}}])


def thread_times(pid):
    """Per-thread CPU milliseconds of a Windows process."""
    ps = (f'(Get-Process -Id {pid}).Threads | ForEach-Object {{ "$($_.Id) $([int]$_.TotalProcessorTime.TotalMilliseconds)" }}')
    out = subprocess.run(['powershell', '-NoProfile', '-Command', ps], capture_output=True, text=True).stdout
    return {int(a): int(b) for a, b in (line.split() for line in out.split('\n') if line.strip())}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tag', required=True)
    ap.add_argument('--cpus', type=int, default=4)
    ap.add_argument('--display', default='gtk')
    ap.add_argument('--disk-cache', default='writeback')
    ap.add_argument('--disk-aio')
    ap.add_argument('--kernel', default=os.path.join(REPO, 'xnu', 'out-0101', 'kernel.development.sweet'))
    ap.add_argument('--boot-args', default='')
    ap.add_argument('--timeout', type=float, default=1500)
    ap.add_argument('--port', type=int, default=4446)
    ap.add_argument('--tmpdir', help="TMP/TEMP for QEMU: where -snapshot keeps its overlay (Windows default: C:'s %%TEMP%%)")
    ap.add_argument('--tap', action='append', default=[], metavar='X,Y',
                    help='after --linger tap X,Y (fractions of the screen) and take two screenshots; repeatable')
    ap.add_argument('--linger', type=float, default=0, metavar='SEC',
                    help='afterwards stay up SEC seconds, a screenshot every 30 s (F1 first when the display is off)')
    ap.add_argument('--powerdown', type=float, default=0, metavar='SEC',
                    help='end with system_powerdown and wait up to SEC for iOS to power off (kernel 0100+), '
                         'instead of quitting QEMU')
    ap.add_argument('--disk', default=DISK, help='root disk image (default: the base image)')
    ap.add_argument('--keep-writes', action='store_true',
                    help='write to --disk instead of a discarded snapshot (use a throwaway overlay, '
                         'e.g. to read the iOS logs afterwards)')
    ap.add_argument('--qemu', default=QEMU if os.path.isfile(QEMU) else None,
                    help='qemu-system-aarch64 to run (default: our 30 ms GTK build, else what tools/qemu-sweet.py finds)')
    ap.add_argument('--safari', metavar='URL', help='afterwards open URL (a-z 0-9 . / -) in Safari, '
                                                    'typed on the hardware keyboard; page-NNs.png every 10 s')
    ap.add_argument('--safari-at', type=float, default=0, metavar='SEC',
                    help='with --safari: not before SEC seconds after start (configd names a new network '
                         'interface only once IOKit is quiet or after 240 s)')
    ap.add_argument('--hmp', action='append', default=[], metavar='SEC:CMD',
                    help='HMP command to run SEC seconds after start (repeatable); output in hmp.txt')
    a = ap.parse_args()

    out = os.path.join(WORK, 'bench', f'{a.tag}-{time.strftime("%Y%m%d-%H%M%S")}')
    os.makedirs(out)
    py = sys.executable
    subprocess.run([py, os.path.join(REPO, 'tools', 'mkadt.py'), os.path.join(out, 'qemu.adt'), '--qemu', '--highmem'],
                   check=True, capture_output=True)
    subprocess.run([py, os.path.join(REPO, 'tools', 'mkpayload.py'), a.kernel, os.path.join(out, 'qemu.adt'),
                    os.path.join(out, 'payload.bin'), '--cmdline', BOOT_ARGS.format(cpus=a.cpus) + ' ' + a.boot_args],
                   check=True, capture_output=True)
    cmd = [py, os.path.join(REPO, 'tools', 'qemu-sweet.py'), os.path.join(out, 'payload.bin'), os.path.join(out, 'run'),
           '--disk', a.disk, '--smp', str(a.cpus), '--display', a.display, '--qmp-tcp', str(a.port),
           '--qemu-log', 'guest_errors,unimp', '--disk-cache', a.disk_cache]
    if not a.keep_writes:
        cmd += ['--snapshot']
    if a.disk_aio:
        cmd += ['--disk-aio', a.disk_aio]
    env = dict(os.environ)
    if a.tmpdir:
        os.makedirs(a.tmpdir, exist_ok=True)
        env['TMP'] = env['TEMP'] = a.tmpdir
    if a.qemu:
        env['QEMU_SYSTEM_AARCH64'] = a.qemu
    res_tmp = env.get('TEMP')
    t0 = time.time()
    launcher = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=open(os.path.join(out, 'launcher.log'), 'w'),
                                env=env)
    deadline = t0 + a.timeout
    qmp = QMP(a.port, t0 + 60)
    qemu_pid = int(subprocess.run(['powershell', '-NoProfile', '-Command',
                                   '(Get-Process qemu-system-aarch64 | Sort-Object StartTime | Select-Object -Last 1).Id'],
                                  capture_output=True, text=True).stdout.strip())
    serial = os.path.join(out, 'run', 'serial.txt')
    sizes, stop_watch = [], threading.Event()
    watcher = threading.Thread(target=watch_size, args=(serial, t0, stop_watch, sizes), daemon=True)
    watcher.start()
    ppm = os.path.join(out, 'screen.ppm')
    res = {'tag': a.tag, 'cpus': a.cpus, 'display': a.display, 'disk_cache': a.disk_cache, 'disk_aio': a.disk_aio,
           'kernel': a.kernel, 'boot_args_extra': a.boot_args, 'tmpdir': res_tmp, 'qemu': a.qemu}
    marks = {}
    times_start = thread_times(qemu_pid)
    t_threads = time.time()

    def log_has(pattern):
        try:
            return re.search(pattern, open(serial, 'rb').read().decode('latin-1')) is not None
        except OSError:
            return False

    pending = sorted((float(sec), cmd) for sec, _, cmd in (h.partition(':') for h in a.hmp))

    def run_due_hmp():
        while pending and time.time() - t0 >= pending[0][0]:
            _, cmd = pending.pop(0)
            try:
                reply = qmp.hmp(cmd)
            except (OSError, ValueError) as e:     # a diagnostic must not end the run
                reply = f'failed: {e!r}'
            with open(os.path.join(out, 'hmp.txt'), 'a', encoding='utf-8') as f:
                f.write(f'=== {time.time() - t0:.1f} s: {cmd}\n{reply}\n')

    def wait(name, cond, poll=1.0, on_poll=None, limit=None, every=12):
        end = min(deadline, time.time() + limit) if limit else deadline
        last = time.time()
        while time.time() < end:
            run_due_hmp()
            if log_has(r'panic\('):
                raise RuntimeError('kernel panic')
            if cond():
                marks[name] = round(time.time() - t0, 1)
                print(f'  {name}: {marks[name]} s', flush=True)
                qmp.call('screendump', filename=os.path.join(out, f'{name}.png'), format='png')
                return True
            if on_poll and time.time() - last > every:
                on_poll()
                last = time.time()
            time.sleep(poll)
        raise TimeoutError(name)

    def flow():
        wait('display_on', lambda: log_has(r'SWEET FB: display on'))
        # The display goes on (logo), off, and on again when SpringBoard brings up the lock
        # screen. A locked iPhone turns its display off after ~10 s without input; when the lock
        # screen draws slowly that comes first and the screen stays black until a key press.
        # Then wake it with F1 (the first press on a dark screen only wakes it).
        wakes = []

        def wake_if_dark():
            try:
                events = re.findall(r'SWEET FB: display (on|off)', open(serial, 'rb').read().decode('latin-1'))
            except OSError:
                return
            if events.count('on') >= 2 and events[-1] == 'off':
                qmp.hmp('sendkey f1 150')
                wakes.append(round(time.time() - t0, 1))
        wait('lockscreen', lambda: screen(qmp, ppm)[1] > 0.002, poll=2, on_poll=wake_if_dark, every=3)
        res['lockscreen_wakes'] = wakes
        # With a wallpaper "lit" no longer tells the screens apart: compare with the previous one.
        lock = screen(qmp, ppm)[2]
        t = time.time()
        qmp.hmp('sendkey f1 150')            # first press may only wake the display
        wait('home', lambda: (lambda s: s[0] > 0.15 and changed(s[2], lock) > 0.25)(screen(qmp, ppm)),
             poll=1, on_poll=lambda: qmp.hmp('sendkey f1 150'))
        marks['home_after_f1'] = round(time.time() - t, 1)
        time.sleep(3)
        home = screen(qmp, ppm)[2]
        t = time.time()
        tap(qmp, *SETTINGS_ICON)
        wait('settings', lambda: (lambda s: s[0] > 0.6 and changed(s[2], home) > 0.3)(screen(qmp, ppm)),
             poll=1, limit=600)
        marks['settings_launch'] = round(time.time() - t, 1)
        time.sleep(3)
        t = time.time()
        qmp.hmp('sendkey f1 150')
        wait('back_home', lambda: changed(screen(qmp, ppm)[2], home) < 0.15, poll=1, limit=300)
        marks['back_home_after_f1'] = round(time.time() - t, 1)
        if a.safari:
            # Safari from the dock, the URL typed on the hardware keyboard (kernel 0096+) into the
            # address field, then a screenshot every 10 s while the page loads (kernel 0095+).
            time.sleep(max(3, a.safari_at - (time.time() - t0)))
            t = time.time()
            tap(qmp, *SAFARI_ICON)
            wait('safari', lambda: (lambda s: s[0] > 0.6 and changed(s[2], home) > 0.3)(screen(qmp, ppm)),
                 poll=1, limit=300)
            marks['safari_launch'] = round(time.time() - t, 1)
            time.sleep(5)
            tap(qmp, *SAFARI_ADDRESS)
            time.sleep(6)                    # the suggestion list takes keys while it opens
            for ch in a.safari:
                qmp.hmp(f'sendkey {QCODES.get(ch, ch)}')
                time.sleep(0.4)
            qmp.hmp('sendkey ret')
            for s in range(10, 100, 10):
                time.sleep(10)
                qmp.call('screendump', filename=os.path.join(out, f'page-{s:02d}s.png'), format='png')

    status = 'ok'
    try:
        try:
            flow()
        except (TimeoutError, RuntimeError) as e:
            status = f'stopped at {e}'
        # --linger: also after a stop, unless the kernel panicked
        for s in range(30, int(a.linger) + 1, 30) if 'panic' not in status else ():
            time.sleep(30)
            events = re.findall(r'SWEET FB: display (on|off)', open(serial, 'rb').read().decode('latin-1'))
            if events[-1:] == ['off']:
                qmp.hmp('sendkey f1 150')
                time.sleep(4)
            qmp.call('screendump', filename=os.path.join(out, f'linger-{s:03d}s.png'), format='png')
        for i, xy in enumerate(a.tap if 'panic' not in status else ()):
            # --tap X,Y: e.g. an app icon on the home screen; screenshots 15 and 45 s later, then Home
            tap(qmp, *(float(v) for v in xy.split(',')))
            for wait_s, name in ((15, 'a'), (30, 'b')):
                time.sleep(wait_s)
                qmp.call('screendump', filename=os.path.join(out, f'tap{i + 1}-{name}.png'), format='png')
            qmp.hmp('sendkey f1 150')
            time.sleep(4)
        if a.linger and 'panic' not in status:
            # Lock with the side button and wake with Home: the lock screen as it is by now
            qmp.hmp('sendkey f2 150')
            time.sleep(4)
            qmp.hmp('sendkey f1 150')
            time.sleep(6)
            qmp.call('screendump', filename=os.path.join(out, 'relock.png'), format='png')
    finally:
        wall = time.time() - t_threads
        times_end = thread_times(qemu_pid)
        deltas = sorted(((times_end[k] - times_start.get(k, 0)) / 1000 for k in times_end), reverse=True)
        res['busiest_thread_pct'] = round(100 * deltas[0] / wall, 1) if deltas else None
        res['qemu_cores_avg'] = round(sum(deltas) / wall, 2) if deltas else None
        blk = qmp.hmp('info blockstats')
        m = re.search(r'root:.*?Read:\s+(\d+)\s+(\d+)\s+(\d+).*?Write:\s+(\d+)\s+(\d+)\s+(\d+)', blk, re.S)
        if m:
            rb, ro, rt, wb, wo, wt = map(int, m.groups())
            res['disk'] = {'read_ops': ro, 'read_mib': rb >> 20, 'read_ms_per_op': round(rt / max(ro, 1) / 1e6, 2),
                           'write_ops': wo, 'write_mib': wb >> 20, 'write_ms_per_op': round(wt / max(wo, 1) / 1e6, 2)}
        try:
            if a.powerdown and 'panic' not in status:
                # The power key (kernel 0100+): iOS syncs, unmounts and powers QEMU off itself.
                t = time.time()
                qmp.call('system_powerdown')
                try:
                    launcher.wait(timeout=a.powerdown)
                    res['powerdown_s'] = round(time.time() - t, 1)
                except subprocess.TimeoutExpired:
                    res['powerdown_s'] = None
                    qmp.hmp('quit')
            else:
                qmp.hmp('quit')
        except OSError:
            pass
        launcher.wait(timeout=60)
        stop_watch.set()
        watcher.join()
        if os.path.exists(serial):
            sizes.append((round(time.time() - t0, 2), os.path.getsize(serial)))
            timestamp_lines(serial, sizes, os.path.join(out, 'run', 'serial-ts.txt'))
    res['status'] = status
    res['marks'] = marks
    json.dump(res, open(os.path.join(out, 'result.json'), 'w'), indent=2)
    print(json.dumps({'tag': a.tag, 'status': status, **marks, 'busiest_thread_pct': res.get('busiest_thread_pct'),
                      'qemu_cores_avg': res.get('qemu_cores_avg'), 'disk': res.get('disk'),
                      'powerdown_s': res.get('powerdown_s')}))
    print(out)


if __name__ == '__main__':
    main()
