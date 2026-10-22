#!/usr/bin/env python3
"""Where does the boot time go? Reads a bench.py run made with boot-arg sweettop=MS (kernel 0092+).

  py -3.12 scripts/dev/boot-profile.py <work>\\bench\\<run> [--top 20]

Splits the boot at the bench milestones (start -> display_on -> lockscreen) and prints for each
phase the CPU time per process (summed over all its pids), page-ins, and how many processes
were started; then the processes started more than once (crash/respawn loops).
"""
import argparse, json, os, re
from collections import Counter, defaultdict

ROW = re.compile(r'TOP (\d+) (.+?) (\d+) (\d+) (-?\d+)$')
HEAD = re.compile(r'TOP --- (\d+) procs (\d+) cpu (\d+)')
TRANSIT = re.compile(r'TOPX (\d+) (.+)$')
EXEC = re.compile(r'^exec (\S+)')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('run')
    ap.add_argument('--top', type=int, default=20)
    a = ap.parse_args()
    res = json.load(open(os.path.join(a.run, 'result.json')))
    marks, cpus = res['marks'], res['cpus']
    bounds = [('start -> display_on', 0.0, marks.get('display_on')),
              ('display_on -> lockscreen', marks.get('display_on'), marks.get('lockscreen'))]
    bounds = [b for b in bounds if b[1] is not None and b[2] is not None]

    def phase_of(t):
        for i, (_, lo, hi) in enumerate(bounds):
            if lo < t <= hi:
                return i
        return None

    lines = []
    # newline='\n': the log has stray carriage returns inside lines
    for line in open(os.path.join(a.run, 'run', 'serial-ts.txt'), encoding='latin-1', newline='\n'):
        t, _, text = line.strip().partition(' ')
        lines.append((float(t), text.replace('\r', '').strip()))
    # Serial lines can reach the host seconds late (main loop stalls); the tables carry the
    # kernel clock, which is host time minus the smallest observed delay.
    offsets = [t - int(m.group(1)) / 1000 for t, text in lines for m in [HEAD.search(text)] if m]
    lag = min(offsets) if offsets else 0.0

    cpu = [defaultdict(float) for _ in bounds]
    pageins = [defaultdict(float) for _ in bounds]
    execs = [Counter() for _ in bounds]
    exec_times = defaultdict(list)
    # A table is printed while proc_iterate walks the processes, and the walk waits for each
    # process that is in the middle of an exec, sometimes for half a minute. So each row is
    # placed at its own arrival time and covers the time since the same pid's previous row
    # (or since the previous table, for a new pid), split over the phases it overlaps.
    last_row, prev_head, slow = {}, 0.0, []
    in_exec = {}                                    # pid -> [name, first seen, last seen]
    for t, text in lines:
        m = TRANSIT.search(text)
        if m:
            seen = in_exec.setdefault(int(m.group(1)), [m.group(2), t - lag, t - lag])
            seen[0], seen[2] = m.group(2), t - lag
            continue
        m = EXEC.match(text)
        if m:
            exec_times[m.group(1)].append(t)
            p = phase_of(t)
            if p is not None:
                execs[p][m.group(1)] += 1
            continue
        m = HEAD.search(text)
        if m:
            kt = int(m.group(1)) / 1000 + lag
            if kt - prev_head > 5:
                slow.append((prev_head, kt))
            prev_head = kt
            continue
        m = ROW.search(text)
        if not m:
            continue
        pid, name, delta, total, pg = int(m.group(1)), m.group(2), int(m.group(3)), int(m.group(4)), int(m.group(5))
        if delta >= 1 << 31:                        # total went down by a few ms
            delta = 0
        delta = min(delta, total)                   # exec: a new task, times restart at 0
        t1 = t - lag
        t0 = min(last_row.get(pid, prev_head), t1)
        last_row[pid] = t1
        span = max(t1 - t0, 1e-6)
        for i, (_, lo, hi) in enumerate(bounds):
            share = max(0.0, min(t1, hi) - max(t0, lo)) / span if t1 > t0 else float(lo < t1 <= hi)
            if share:
                cpu[i][name] += delta * share
                pageins[i][name] += pg * share

    if offsets:
        print(f'serial lines reach the host {lag:.2f} .. {max(offsets):.2f} s after the kernel prints them')
    for lo, hi in slow:
        print(f'one table took {lo:.1f} -> {hi:.1f} s (waited for a process in exec)')
    for i, (name, lo, hi) in enumerate(bounds):
        wall = hi - lo
        total = sum(cpu[i].values()) / 1000
        print(f'\n== {name}: {lo:.1f} -> {hi:.1f} s ({wall:.1f} s wall)')
        print(f'   CPU used by processes: {total:.1f} s = {total / wall:.2f} of {cpus} vCPUs busy; '
              f'{sum(execs[i].values())} execs')
        print(f'   {"process":32} {"cpu s":>7} {"share":>6} {"pageins":>8} {"execs":>5}')
        for proc, ms in sorted(cpu[i].items(), key=lambda kv: -kv[1])[:a.top]:
            print(f'   {proc[:32]:32} {ms / 1000:7.1f} {100 * ms / max(1, total * 1000):5.1f}% '
                  f'{pageins[i][proc]:8.0f} {execs[i].get(proc, 0):5d}')
    stuck = sorted((v for v in in_exec.values() if v[2] - v[1] >= 4), key=lambda v: v[1])
    if stuck:
        print('\n== stuck in exec (or in creation) for 4 s or more')
        for name, lo, hi in stuck:
            print(f'   {name:32} {lo:6.1f} -> {hi:6.1f} s ({hi - lo:.0f} s)')
    loops = {n: ts for n, ts in exec_times.items() if len(ts) > 1 and n != 'xpcproxy'}
    if loops:
        print('\n== started more than once (exec times, s)')
        for n, ts in sorted(loops.items(), key=lambda kv: -len(kv[1])):
            print(f'   {n:32} x{len(ts):<3} ' + ' '.join(f'{t:.0f}' for t in ts[:12]) +
                  (' ...' if len(ts) > 12 else ''))


if __name__ == '__main__':
    main()
