#!/usr/bin/env python3
"""Hand the .ipa files in a Windows folder to iOS (asoftinstalld) while it runs.

  py -3.12 scripts/ipa-server.py --dir DIR [--port 8765]

Listens on 127.0.0.1 only; inside QEMU's user network iOS reaches it as 10.0.2.2. asoftinstalld
(apps/asoftinstalld) asks every 10 s:
  GET  /list           names of the .ipa files waiting in DIR, one per line
  GET  /ipa/NAME       the file
  POST /done/NAME      body "installed" or "failed: ..."; NAME moves to DIR\\Installed or
                       DIR\\Failed with NAME.log next to it
run-windows.ps1 starts it with the emulator.
"""
import argparse, http.server, os, shutil, sys, urllib.parse


def make_handler(folder):
    class Handler(http.server.BaseHTTPRequestHandler):
        def name(self, prefix):
            name = urllib.parse.unquote(self.path[len(prefix):])
            # a plain file name in DIR, nothing else
            if not name.lower().endswith('.ipa') or os.path.basename(name) != name or name.startswith('.'):
                return None
            return name

        def reply(self, code, body=b'', ctype='text/plain; charset=utf-8'):
            self.send_response(code)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == '/list':
                names = sorted(n for n in os.listdir(folder)
                               if n.lower().endswith('.ipa') and os.path.isfile(os.path.join(folder, n)))
                return self.reply(200, ''.join(n + '\n' for n in names).encode())
            name = self.name('/ipa/') if self.path.startswith('/ipa/') else None
            path = name and os.path.join(folder, name)
            if not path or not os.path.isfile(path):
                return self.reply(404)
            with open(path, 'rb') as f:
                data = f.read()
            print(f'ipa-server: sending {name} ({len(data)} bytes)', flush=True)
            self.reply(200, data, 'application/octet-stream')

        def do_POST(self):
            name = self.name('/done/') if self.path.startswith('/done/') else None
            body = self.rfile.read(int(self.headers.get('Content-Length', 0) or 0)).decode('utf-8', 'replace')
            path = name and os.path.join(folder, name)
            if not path or not os.path.isfile(path):
                return self.reply(404)
            dest = os.path.join(folder, 'Installed' if body.startswith('installed') else 'Failed')
            os.makedirs(dest, exist_ok=True)
            shutil.move(path, os.path.join(dest, name))
            with open(os.path.join(dest, name + '.log'), 'w', encoding='utf-8') as f:
                f.write(body.strip() + '\n')
            print(f'ipa-server: {name}: {body.strip()}', flush=True)
            self.reply(200)

        def log_message(self, fmt, *args):
            pass                        # /list every 10 s would flood the console

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--dir', required=True)
    ap.add_argument('--port', type=int, default=8765)
    a = ap.parse_args()
    os.makedirs(a.dir, exist_ok=True)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', a.port), make_handler(a.dir))
    print(f'ipa-server: drop .ipa files into {a.dir} (iOS asks http://10.0.2.2:{a.port})', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    sys.exit(main())
