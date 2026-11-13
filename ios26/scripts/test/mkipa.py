"""mkipa.py OUT.ipa [encrypted|apple]: a made-up .ipa (a SHA-1 main executable and a SHA-256 library, both with
get-task-allow, an unsigned library, a data file, an empty folder) built with the phone test's Mach-O builders. For ipa-chain.ps1."""
import hashlib, os, plistlib, struct, sys, zipfile

src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'adhoc_test.py')).read()
a = src.index('# -- fixtures')
b = src.index('def slice_state')
exec(src[a:b])

out = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else ''
bid = 'com.apple.fake' if mode == 'apple' else 'com.example.fake'
ents = plistlib.dumps({'get-task-allow': True, 'application-identifier': 'X.com.example.fake'}, fmt=plistlib.FMT_XML)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('Payload/Fake.app/Info.plist', plistlib.dumps({'CFBundleIdentifier': bid, 'CFBundleExecutable': 'Fake', 'CFBundleShortVersionString': '1.0'}, fmt=plistlib.FMT_BINARY))
    z.writestr('Payload/Fake.app/Fake', signed(1, ents=ents, filetype=2))             # SHA-1 only, get-task-allow
    z.writestr('Payload/Fake.app/Frameworks/Lib.framework/Lib', signed(2, ents=ents))  # SHA-256, a library with entitlements
    z.writestr('Payload/Fake.app/Frameworks/Raw.dylib', macho())                      # unsigned
    if mode == 'encrypted':
        z.writestr('Payload/Fake.app/Frameworks/Enc.dylib', macho(cryptid=1))
    z.writestr('Payload/Fake.app/data.bin', os.urandom(5000))
    z.writestr('Payload/Fake.app/Assets/empty/', b'')
print('made', out)
