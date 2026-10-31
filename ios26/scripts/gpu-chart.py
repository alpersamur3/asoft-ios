#!/usr/bin/env python3
"""The README's chart of the QEMU process's GPU use, from gpu-sample.ps1's rows: its 3D engine on
each GPU and its dedicated memory, in two panels over one time axis, with a line at each gesture.
    python gpu-chart.py gpu.csv out.png --main LUID --other LUID --main-name "RTX 4080 Laptop"
                        --other-name "Intel UHD" [--events events.txt] [--until SECONDS]
events.txt: a line per gesture, its Unix time first.
"""
import argparse
import csv
from collections import defaultdict

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

SURFACE = '#fcfcfb'
TEXT = '#0b0b0b'
MUTED = '#52514e'
GRID = '#e6e5e0'
FIRST, SECOND = '#2a78d6', '#eb6834'


def main():
    p = argparse.ArgumentParser()
    p.add_argument('csv')
    p.add_argument('out')
    p.add_argument('--main', required=True)
    p.add_argument('--other', required=True)
    p.add_argument('--main-name', default='main GPU')
    p.add_argument('--other-name', default='other GPU')
    p.add_argument('--events')
    p.add_argument('--until', type=float)
    a = p.parse_args()

    engine, memory = defaultdict(dict), {}
    t0 = None
    with open(a.csv) as f:
        for r in csv.DictReader(f):
            t = float(r['t'])
            t0 = t if t0 is None else t0
            at = t - t0
            if a.until and at > a.until:
                continue
            value = float(r['value'])
            # Windows' formatted counters now and then read past 100: a glitch
            if r['kind'] == 'engine' and r['key'] == '3D' and value <= 100:
                engine[r['luid']][at] = value
            elif r['kind'] == 'mem' and r['key'] == 'dedicated_mb' and r['luid'] == a.main:
                memory[at] = value / 1024
    gestures = []
    if a.events:
        with open(a.events) as f:
            gestures = [float(line.split()[0]) - t0 for line in f if line.strip()]
    if a.until:
        gestures = [g for g in gestures if g <= a.until]

    plt.rcParams.update({'font.size': 11, 'text.color': TEXT, 'axes.labelcolor': MUTED,
                         'xtick.color': MUTED, 'ytick.color': MUTED})
    fig, (top, bottom) = plt.subplots(2, 1, figsize=(9.4, 5.4), sharex=True, dpi=120,
                                      height_ratios=[3, 2], facecolor=SURFACE)
    for ax in (top, bottom):
        ax.set_facecolor(SURFACE)
        ax.grid(axis='y', color=GRID, linewidth=1)
        ax.set_axisbelow(True)
        ax.tick_params(length=0)
        for side in ('top', 'right', 'left'):
            ax.spines[side].set_visible(False)
        ax.spines['bottom'].set_color(GRID)
        for g in gestures:
            ax.axvline(g, color='#c9c8c2', linewidth=0.8, zorder=1)

    other = sorted(engine[a.other].items())
    main_ = sorted(engine[a.main].items())
    top.plot(*zip(*other), color=SECOND, linewidth=2, solid_joinstyle='round', zorder=2,
             label=a.other_name)
    top.plot(*zip(*main_), color=FIRST, linewidth=2, solid_joinstyle='round', zorder=3,
             label=a.main_name)
    top.set_ylim(0, 100)
    top.set_ylabel('3D engine, %')
    top.legend(loc='upper left', frameon=False, ncol=2)
    top.set_title("The QEMU process running iOS 26, as Windows counts its GPU use", loc='left',
                  fontsize=13, pad=26)
    if gestures:
        top.text(0, 1.03, 'Each grey line: a tap, swipe or button', color=MUTED, fontsize=10,
                 transform=top.transAxes)

    mem = sorted(memory.items())
    bottom.plot(*zip(*mem), color=FIRST, linewidth=2, solid_joinstyle='round', zorder=3)
    bottom.set_ylim(0, max(v for _, v in mem) * 1.2)
    bottom.set_ylabel(f'{a.main_name}\nmemory, GB')
    bottom.set_xlabel('seconds since QEMU started')
    fig.tight_layout()
    fig.savefig(a.out, facecolor=SURFACE)


if __name__ == '__main__':
    main()
