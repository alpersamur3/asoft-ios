"""Give iOS 26 the PC's time zone, region format and 12/24-hour clock through the guest's root shell
(com.asoft.bash on the serial console, which the launcher puts on TCP 127.0.0.1:4451): what
asoftinstalld does in the iOS 16 guest, without a daemon in this one. Start-iOS26.ps1 starts it on a
cold boot when the PC's values differ from what was applied to the disk last.

    guest-clock.py PORT WAIT [--tz Europe/Istanbul] [--region TR] [--clock 24|12]
                   [--state FILE] [--pid N] [--log FILE]

--tz: /private/var/db/timezone/localtime becomes a link to /var/db/timezone/zoneinfo/<tz> (a new link
renamed over the old one, never a moment without a time zone). --region, --clock: AppleLocale and
the first of AppleLanguages (iOS's language with the PC's region: English with TR is en_TR and
en-TR) and AppleICUForce24HourTime or AppleICUForce12HourTime in mobile's .GlobalPreferences.plist.
The guest has no defaults, plutil or notifyutil: the plist comes over the console in base64, is
edited here and goes back the same way, once SpringBoard runs and the shell answers quickly (iOS's
start-up keeps it slow for minutes), and cfprefsd is restarted so it reads the new file. Nothing
can post the change notifications, and SpringBoard starts as early as the shell, so SpringBoard is
restarted afterwards (Settings restarts it too when the region changes).
--state: once everything is applied, the values given are merged into FILE (Key=Value lines), which
the launcher compares with the PC's at the next start. --pid: give up when that process (QEMU) ends.
Exit 0 when every value given was applied, 1 if one was not.
"""
import argparse, base64, ctypes, hashlib, importlib.util, os, plistlib, re, sys, time

here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('guest_shell', os.path.join(here, 'guest-shell.py'))
shell = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(shell)

LINK = '/private/var/db/timezone/localtime'
ZONES = '/var/db/timezone/zoneinfo/'
PREFS = '/private/var/mobile/Library/Preferences/.GlobalPreferences.plist'
PARTS = '/private/var/tmp/asoft-clock.'
B64 = re.compile(r'^[A-Za-z0-9+/=]+$')
log = print


def alive(pid):
    if not pid:
        return True
    k = ctypes.windll.kernel32
    h = k.OpenProcess(0x1000, False, pid)       # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return False
    code = ctypes.c_ulong()
    ok = k.GetExitCodeProcess(h, ctypes.byref(code))
    k.CloseHandle(h)
    return bool(ok) and code.value == 259       # STILL_ACTIVE


class Guest:
    def __init__(self, port, wait, pid):
        self.port, self.until, self.pid, self.s = port, time.time() + wait, pid, None

    def up(self):
        # QEMU listens from its start; the shell answers once launchd has started it
        while time.time() < self.until and alive(self.pid):
            if self.s is None:
                self.s = shell.connect(self.port, min(self.until, time.time() + 10))
                if self.s is None:
                    continue
                self.s.sendall(b'\r')
            try:
                if shell.run(self.s, 'true', min(self.until, time.time() + 20)) is not None:
                    return True
            except OSError:
                self.s.close()
                self.s = None
                time.sleep(2)
        return False

    def sh(self, cmd, retry=90):
        """The command's output (it may run twice: idempotent commands only), None without one.
        Sent again only after retry seconds: while iOS starts up a command can take half a minute,
        and one sent again sooner queues behind it."""
        if not alive(self.pid):
            return None
        try:
            return shell.run(self.s, cmd, self.until, retry)
        except OSError as e:
            log('console: %s' % e)
            return None

    def settle(self, limit=480):
        """Wait until SpringBoard runs and three commands in a row each answer within 3 s (or limit
        seconds pass): before that, iOS's start-up keeps the shell slow and the kernel's messages
        thick on the console."""
        until, quick = min(self.until, time.time() + limit), 0
        while quick < 3 and time.time() < until:
            t = time.time()
            out = self.sh('ps -axo comm=')
            if out is None:
                return None
            quick = quick + 1 if time.time() - t < 3 and re.search(r'(^|/)SpringBoard\s*$', out, re.M) else 0
            time.sleep(2)
        return quick >= 3


def answer(g, cmd, want, tries=3):
    """Run cmd until its output holds want (a regex); the match, None. The kernel's messages share
    the console and can land in the middle of a line, so an answer is looked for, not parsed."""
    for _ in range(tries):
        out = g.sh(cmd)
        if out is None:
            return None
        m = re.search(want, out)
        if m:
            return m
    return None


def set_zone(g, zone):
    if not re.fullmatch(r'[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*', zone):
        log('time zone %s: not a zone name' % zone)
        return False
    target = ZONES + zone
    m = answer(g, 'test -f %s && { test "$(readlink %s)" = %s || { ln -sfn %s %s.asoft && mv -fT %s.asoft %s; }; } '
                  '&& test "$(readlink %s)" = %s && echo zone-set || echo zone-not-set'
               % (target, LINK, target, target, LINK, LINK, LINK, LINK, target), r'zone-(not-)?set')
    if not m or m.group(1):
        log('time zone %s: not set (%s)' % (zone, 'no such zone, or the link not made' if m else 'no answer'))
        return False
    log('time zone %s' % zone)
    return True


def read_file(g, path):
    """The guest file's bytes (b'' when there is none), None if not read: a copy, read in blocks
    that each come with their sha256 and are asked for again until they match it."""
    copy, bs = PARTS + 'read', 768
    m = answer(g, 'if test -f %s; then cp %s %s && echo "size=$(stat -c %%s %s)=size"; else echo size=none=size; fi'
               % (path, path, copy, copy), r'size=(\d+|none)=size')
    if not m:
        return None
    if m.group(1) == 'none':
        return b''
    data = b''
    for i in range((int(m.group(1)) + bs - 1) // bs):
        for _ in range(8):
            out = g.sh('echo "sum=$(dd if=%s bs=%d skip=%d count=1 2>/dev/null | sha256sum)"; '
                       'dd if=%s bs=%d skip=%d count=1 2>/dev/null | base64 -w0; echo'
                       % (copy, bs, i, copy, bs, i))
            if out is None:
                return None
            sums = re.findall(r'sum=([0-9a-f]{64})', out)
            got = None
            for line in out.splitlines():
                line = line.strip()
                if sums and B64.match(line) and len(line) % 4 == 0:
                    raw = base64.b64decode(line)
                    if hashlib.sha256(raw).hexdigest() == sums[0]:
                        got = raw
            if got is not None:
                data += got
                break
        else:
            return None
    g.sh('rm -f %s' % copy)
    return data


def read_prefs(g):
    """mobile's global preferences as a dict ({} when there is no file), None if not read."""
    raw = read_file(g, PREFS)
    if raw is None:
        log('%s: not read over the console' % PREFS)
        return None
    return plistlib.loads(raw) if raw else {}


def write_prefs(g, raw):
    text = base64.b64encode(raw).decode()
    if g.sh('rm -f %s*' % PARTS) is None:
        return False
    for i in range(0, len(text), 512):
        # one file per piece: a piece sent twice writes the same file again
        if g.sh("printf %%s '%s' > %s%03d" % (text[i:i + 512], PARTS, i // 512)) is None:
            return False
    # owner and mode of the file it replaces (mobile, 600), renamed over it; run once: the
    # pieces are gone afterwards, so it is checked by the file's hash below, not by its answer
    new = PREFS + '.asoft'
    g.sh('cat %s[0-9]* | base64 -d > %s && test "$(sha256sum < %s)" = "%s  -" && '
         '{ chown --reference=%s %s 2>/dev/null || chown 501:501 %s; } && '
         '{ chmod --reference=%s %s 2>/dev/null || chmod 600 %s; } && mv -fT %s %s; rm -f %s %s*'
         % (PARTS, new, new, hashlib.sha256(raw).hexdigest(), PREFS, new, new, PREFS, new, new, new, PREFS, new,
            PARTS))
    return has_prefs(g, raw)


def has_prefs(g, raw):
    m = answer(g, 'echo "sum=$(sha256sum < %s)=sum"' % PREFS, r'sum=([0-9a-f]{64})  -=sum')
    return bool(m) and m.group(1) == hashlib.sha256(raw).hexdigest()


def set_region(prefs, region):
    """iOS's first language with the PC's region, as iOS 26's Settings writes English with Türkiye:
    AppleLocale en_TR and the first of AppleLanguages en-TR (iOS 16's asoftinstalld set AppleLocale
    alone; iOS 26's lock screen dates by the language, and showed en_TR's dates US style without)."""
    langs = prefs.get('AppleLanguages')
    langs = list(langs) if isinstance(langs, list) and langs and isinstance(langs[0], str) else ['en']
    parts = re.split(r'[-_]', langs[0].split('@')[0])
    lang = [parts[0].lower()] + [p for p in parts[1:] if len(p) == 4 and p.isalpha()][:1]   # zh-Hans
    langs[0] = '-'.join(lang + [region])
    prefs['AppleLanguages'] = langs
    prefs['AppleLocale'] = '_'.join(lang + [region])


def restart(g, names):
    """Kill these processes (launchd starts them again); the names of those that ran. The pids are
    picked here and killed by number, so a kill sent twice cannot hit the process started again."""
    want = r'^\s*(\d+)\s+(?:\S*/)?(%s)\s*$' % '|'.join(map(re.escape, names))
    for _ in range(3):
        found = re.findall(want, g.sh('ps -axo pid=,comm=') or '', re.M)
        if found:
            g.sh('kill %s; true' % ' '.join(p for p, _ in found))
            return sorted(set(n for _, n in found))
    return []


def main():
    a = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    a.add_argument('port', type=int)
    a.add_argument('wait', type=float)
    a.add_argument('--tz', default='')
    a.add_argument('--region', default='')
    a.add_argument('--clock', default='', choices=['', '12', '24'])
    a.add_argument('--state', default='')
    a.add_argument('--pid', type=int, default=0)
    a.add_argument('--log', default='')
    o = a.parse_args()
    global log
    if o.log:
        f = open(o.log, 'a', encoding='utf-8')
        log = lambda m: (f.write('%s %s\n' % (time.strftime('%H:%M:%S'), m)), f.flush())
    if o.region and not re.fullmatch(r'[A-Z]{2}|[0-9]{3}', o.region):
        log('region %s: not a region code' % o.region)
        o.region = ''
    g = Guest(o.port, o.wait, o.pid)
    if not g.up():
        log('no shell on port %d within %d s (or QEMU ended)' % (o.port, o.wait))
        return 1
    log('shell up')
    ok, done = True, {}
    if o.tz:
        if set_zone(g, o.tz):
            done['TimeZone'] = o.tz
        else:
            ok = False
    if o.region or o.clock:
        settled = g.settle()
        if settled is not None:
            log('iOS settled' if settled else 'iOS still busy after 8 min; going on')
        prefs = read_prefs(g)
        if prefs is None:
            ok = False
        else:
            if o.region:
                set_region(prefs, o.region)
            if o.clock:
                h24 = o.clock == '24'
                prefs.pop('AppleICUForce12HourTime' if h24 else 'AppleICUForce24HourTime', None)
                prefs['AppleICUForce24HourTime' if h24 else 'AppleICUForce12HourTime'] = True
            # cfprefsd keeps the file it read; restarted, it reads ours (and must not have put its own back)
            raw = plistlib.dumps(prefs, fmt=plistlib.FMT_BINARY)
            written = write_prefs(g, raw)
            if written:
                restart(g, ['cfprefsd'])
            if written and has_prefs(g, raw):
                if o.region:
                    done['Region'] = o.region
                    log('region %s (%s, %s)' % (o.region, prefs['AppleLocale'], prefs['AppleLanguages'][0]))
                if o.clock:
                    done['Clock'] = o.clock
                    log('%s-hour clock' % o.clock)
            else:
                log('%s: not written' % PREFS)
                ok = False
    if done:
        # processes that had read the old values keep them: nothing here can post the notifications
        ran = restart(g, ['SpringBoard'])
        log('restarted %s' % ', '.join(ran) if ran else 'SpringBoard not found to restart')
        g.sh('sync')
    if done and o.state:
        state = {}
        if os.path.exists(o.state):
            for line in open(o.state, encoding='utf-8'):
                k, _, v = line.strip().partition('=')
                if k:
                    state[k] = v
        state.update(done)
        with open(o.state + '.tmp', 'w', encoding='utf-8') as out:
            out.write(''.join('%s=%s\n' % kv for kv in sorted(state.items())))
        os.replace(o.state + '.tmp', o.state)
    log('done' if ok else 'not all applied')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
