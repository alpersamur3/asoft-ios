#!/usr/bin/env python3
"""ASoftware iOS: a small window next to the iOS (QEMU) window with the phone's buttons, screenshots,
installing an .ipa and shutting down.

  pyw -3.12 scripts/control-panel.py [--port 4445] [--ipa-dir DIR] [--shots DIR]

run-windows.ps1 starts it with QEMU. It talks to QEMU over QMP (qemu-sweet.py --qmp-tcp PORT), one
short connection per action, so scripts/dev/qmp.py and the like keep working alongside it.
  Home, Lock, Volume -/+  the keys F1, F2, F3, F4 (kernel 0096 turns them into the phone's buttons)
  Screenshot              a PNG in --shots (default: Pictures\\iOS Screenshots), tagged
                          "Software: ASoftware iOS Emulator"
  Fit window              View > Best Fit (Ctrl+Alt+0) in the QEMU window: with qemu/patches/0005
                          the window takes the phone's shape (1080:2400) at ~92 % of the screen's
                          height, so iOS fills it without bars (QEMU does that by itself at boot)
  Install .ipa...         copies the file into --ipa-dir; asoftinstalld fetches it through
                          scripts/ipa-server.py and the result shows here (Installed\\ or Failed\\)
  Shut down               system_powerdown: iOS syncs, unmounts and turns QEMU off (kernel 0100);
                          pressed again it quits QEMU at once
The window sits to the right of the QEMU window and closes by itself once QEMU is gone.

Copyright (c) 2026 ASoftware. MIT License, see LICENSE.
"""
import argparse, ctypes, json, os, shutil, socket, threading, time, zlib
import tkinter as tk
from ctypes import wintypes
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

KEYS = {'Home': 'f1', 'Lock': 'f2', 'Volume −': 'f3', 'Volume +': 'f4'}


def qmp(port, *commands):
    """Run QMP commands [(name, arguments), ...] on a new connection; returns the last reply."""
    with socket.create_connection(('127.0.0.1', port), timeout=5) as sock:
        f = sock.makefile('rwb')
        json.loads(f.readline())                         # greeting
        reply = None
        for name, args in [('qmp_capabilities', {})] + list(commands):
            f.write(json.dumps({'execute': name, 'arguments': args}).encode() + b'\n')
            f.flush()
            while True:
                reply = json.loads(f.readline())
                if 'return' in reply or 'error' in reply:  # skip asynchronous events
                    break
            if 'error' in reply:
                raise RuntimeError(reply['error'].get('desc', 'QMP error'))
        return reply['return']


def tag_png(path):
    """Mark a screenshot as ours: a PNG tEXt chunk "Software" right after IHDR."""
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        return
    end = 8 + 12 + int.from_bytes(data[8:12], 'big')     # signature, then IHDR (length, type, data, CRC)
    body = b'Software\0ASoftware iOS Emulator'
    chunk = len(body).to_bytes(4, 'big') + b'tEXt' + body + zlib.crc32(b'tEXt' + body).to_bytes(4, 'big')
    path.write_bytes(data[:end] + chunk + data[end:])


# --- the QEMU window (Win32) -------------------------------------------------------------------

user32 = ctypes.windll.user32 if os.name == 'nt' else None


def qemu_window():
    """The largest visible top-level window of a qemu-system process, or None."""
    kernel32 = ctypes.windll.kernel32
    found = []

    def visit(hwnd, _):
        if not user32.IsWindowVisible(hwnd):
            return True
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        proc = kernel32.OpenProcess(0x1000, False, pid.value)        # PROCESS_QUERY_LIMITED_INFORMATION
        if proc:
            name = ctypes.create_unicode_buffer(512)
            size = wintypes.DWORD(512)
            if kernel32.QueryFullProcessImageNameW(proc, 0, name, ctypes.byref(size)) and \
                    os.path.basename(name.value).lower().startswith('qemu-system'):
                r = wintypes.RECT()
                user32.GetWindowRect(hwnd, ctypes.byref(r))
                found.append(((r.right - r.left) * (r.bottom - r.top), hwnd))
            kernel32.CloseHandle(proc)
        return True
    user32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)(visit), 0)
    return max(found)[1] if found else None


def window_rect(hwnd):
    r = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(r))
    return r.left, r.top, r.right - r.left, r.bottom - r.top


def best_fit(hwnd):
    """View > Best Fit (Ctrl+Alt+0) in the QEMU window. Moving or resizing a GTK window from
    outside does not stick (GTK sets its own size again), so QEMU sizes it (qemu/patches/0005)."""
    user32.SetForegroundWindow(hwnd)
    time.sleep(0.3)
    keys = (0x11, 0x12, 0x30)                            # VK_CONTROL, VK_MENU (Alt), '0'
    for vk in keys:
        user32.keybd_event(vk, 0, 0, 0)
    for vk in reversed(keys):
        user32.keybd_event(vk, 0, 2, 0)                  # KEYEVENTF_KEYUP


class Panel:
    def __init__(self, root, a):
        self.root, self.port = root, a.port
        self.ipa_dir, self.shots = Path(a.ipa_dir), Path(a.shots)
        self.pending = {}                                # .ipa name -> time it was copied
        self.connected = False
        self.docked = None                               # (time of the first dock, QEMU window rect)
        self.misses = 0
        self.powering_down = False

        root.title('ASoftware')
        root.resizable(False, False)
        frame = ttk.Frame(root, padding=10)
        frame.grid()
        for i, label in enumerate(KEYS):
            ttk.Button(frame, text=label, width=14,
                       command=lambda key=KEYS[label]: self.run(self.key, key)).grid(row=i // 2, column=i % 2, padx=3, pady=3)
        ttk.Button(frame, text='Screenshot', width=14, command=lambda: self.run(self.screenshot)).grid(row=2, column=0, padx=3, pady=3)
        ttk.Button(frame, text='Open folder', width=14, command=self.open_shots).grid(row=2, column=1, padx=3, pady=3)
        ttk.Button(frame, text='Fit window', command=self.fit).grid(row=3, column=0, columnspan=2, sticky='ew', padx=3, pady=3)
        ttk.Button(frame, text='Install .ipa…', command=self.install).grid(row=4, column=0, columnspan=2, sticky='ew', padx=3, pady=3)
        self.power = ttk.Button(frame, text='Shut down', command=self.shut_down)
        self.power.grid(row=5, column=0, columnspan=2, sticky='ew', padx=3, pady=(10, 3))
        self.status = ttk.Label(frame, text='Waiting for QEMU…', width=34, wraplength=260, foreground='#555')
        self.status.grid(row=6, column=0, columnspan=2, sticky='w', padx=3, pady=(8, 0))
        ttk.Label(frame, text='ASoftware', foreground='#aaa', font=('Segoe UI', 8)).grid(
            row=7, column=0, columnspan=2, sticky='e', padx=3, pady=(6, 0))
        root.after(1000, self.poll)

    def say(self, text):
        self.root.after(0, lambda: self.status.config(text=text))

    def run(self, action, *args):
        """Actions talk to QEMU off the UI thread."""
        def work():
            try:
                action(*args)
            except (OSError, RuntimeError, ValueError) as e:
                self.say(f'QEMU did not answer: {e}')
        threading.Thread(target=work, daemon=True).start()

    def key(self, qcode):
        qmp(self.port, ('send-key', {'keys': [{'type': 'qcode', 'data': qcode}], 'hold-time': 150}))

    def screenshot(self):
        self.shots.mkdir(parents=True, exist_ok=True)
        path = self.shots / time.strftime('iOS %Y-%m-%d %H.%M.%S.png')
        qmp(self.port, ('screendump', {'filename': str(path), 'format': 'png'}))
        tag_png(path)
        self.say(f'Saved {path.name}')

    def open_shots(self):
        self.shots.mkdir(parents=True, exist_ok=True)
        os.startfile(self.shots)

    def dock(self):
        """Sit to the right of the QEMU window; False while there is no window."""
        try:
            hwnd = qemu_window()
            if not hwnd:
                return False
            rect = window_rect(hwnd)
            self.docked = (self.docked[0] if self.docked else time.time(), rect)
            x, y, width, _ = rect
            self.root.geometry(f'+{x + width}+{y}')
            return True
        except (AttributeError, OSError):
            return False

    def fit(self):
        hwnd = qemu_window()
        if hwnd:
            threading.Thread(target=best_fit, args=(hwnd,), daemon=True).start()
            self.root.after(1500, self.dock)

    def install(self):
        names = filedialog.askopenfilenames(title='Install .ipa', filetypes=[('iOS apps', '*.ipa'), ('All files', '*.*')])
        if not names:
            return
        self.ipa_dir.mkdir(parents=True, exist_ok=True)
        for name in names:
            dest = self.ipa_dir / Path(name).name
            try:
                shutil.copyfile(name, dest)
            except OSError as e:
                messagebox.showerror('Install .ipa', f'Could not copy {name}:\n{e}')
                continue
            self.pending[dest.name] = time.time()
        self.say(f'Installing {", ".join(Path(n).name for n in names)}… (iOS picks it up within ~10 s)')

    def shut_down(self):
        if not self.powering_down:
            self.powering_down = True
            self.power.config(text='Force quit')
            self.say('Shutting down… (iOS turns QEMU off in ~10 s)')
            self.run(lambda: qmp(self.port, ('system_powerdown', {})))
        elif messagebox.askyesno('Force quit', 'Quit QEMU now, without letting iOS shut down?'):
            self.run(lambda: qmp(self.port, ('quit', {})))

    def install_results(self):
        for name, since in list(self.pending.items()):
            for where in ('Installed', 'Failed'):
                log = self.ipa_dir / where / (name + '.log')
                if log.exists() and log.stat().st_mtime >= since - 1:
                    result = log.read_text(encoding='utf-8', errors='replace').strip()
                    self.say(f'{name}: {result[:300]}')
                    del self.pending[name]

    def follow(self):
        """QEMU resizes and moves its window when iOS sets up its screen: in the first two
        minutes stay next to it; later the panel stays where the user puts it."""
        if self.docked and time.time() - self.docked[0] < 120:
            hwnd = qemu_window()
            if hwnd and window_rect(hwnd) != self.docked[1]:
                self.dock()

    def poll(self):
        """Every 2 s: is QEMU still there (close with it), and have pending installs finished."""
        def check():
            try:
                qmp(self.port, ('query-status', {}))
                ok = True
            except (OSError, RuntimeError, ValueError):
                ok = False
            # A busy boot can keep QMP from answering in time: QEMU is gone only when its window is
            gone = not ok and qemu_window() is None
            self.root.after(0, lambda: self.polled(ok, gone))
        threading.Thread(target=check, daemon=True).start()

    def polled(self, ok, gone):
        if ok:
            if not self.docked:
                self.dock()                              # the QEMU window appears a little after QMP
            else:
                self.follow()
            if not self.connected:
                self.say('iOS is running. F1-F4 also work in the iOS window.')
            self.connected, self.misses = True, 0
        elif self.connected and gone:
            self.misses += 1
            if self.misses >= 2:                         # QEMU has quit
                self.root.destroy()
                return
        self.install_results()
        self.root.after(2000, self.poll)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--port', type=int, default=4445)
    ap.add_argument('--ipa-dir', required=True)
    ap.add_argument('--shots', default=str(Path.home() / 'Pictures' / 'iOS Screenshots'))
    a = ap.parse_args()
    try:
        # Sharp text on scaled displays (Tk is otherwise bitmap-stretched by Windows), and window
        # coordinates in physical pixels, as Win32 reports the QEMU window's
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except (AttributeError, OSError):
        pass
    root = tk.Tk()
    Panel(root, a)
    root.mainloop()


if __name__ == '__main__':
    main()
