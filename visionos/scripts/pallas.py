"""Ask Apple's asset server (Pallas, gdmf.apple.com/v2/assets, no account) for a MobileAsset and write the one of
the build asked for as JSON: its URL, size, archive decryption key and Apple's own fields.

    pallas.py OUT_JSON --type ASSET_TYPE --audience UUID --build BUILD [--size BYTES] [--path RELATIVE_PATH]

--size and --path pin what the answer must say (the installer's pins); a different answer is refused, so a
changed asset never gets downloaded unnoticed. The TLS connection is verified: gdmf.apple.com's chain ends at
Apple Root CA, which Python's own store (certifi on Linux, Windows' store as Python sees it) may not have, so it
is checked against that root only, embedded below and pinned by its SHA-256.
"""
import argparse, base64, hashlib, json, ssl, sys, urllib.request

# Apple Root CA (2006-04-25 .. 2035-02-09), https://www.apple.com/appleca/AppleIncRootCertificate.cer
APPLE_ROOT_SHA256 = 'b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024'
APPLE_ROOT_PEM = """-----BEGIN CERTIFICATE-----
MIIEuzCCA6OgAwIBAgIBAjANBgkqhkiG9w0BAQUFADBiMQswCQYDVQQGEwJVUzET
MBEGA1UEChMKQXBwbGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlv
biBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwHhcNMDYwNDI1MjE0
MDM2WhcNMzUwMjA5MjE0MDM2WjBiMQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBw
bGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkx
FjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
ggEKAoIBAQDkkakJH5HbHkdQ6wXtXnmELes2oldMVeyLGYne+Uts9QerIjAC6Bg+
+FAJ039BqJj50cpmnCRrEdCju+QbKsMflZ56DKRHi1vUFjczy8QPTc4UadHJGXL1
XQ7Vf1+b8iUDulWPTV0N8WQ1IxVLFVkds5T39pyez1C6wVhQZ48ItCD3y6wsIG9w
tj8BMIy3Q88PnT3zK0koGsj+zrW5DtleHNbLPbU6rfQPDgCSC7EhFi501TwN22IW
q6NxkkdTVcGvL0Gz+PvjcM3mo0xFfh9Ma1CWQYnEdGILEINBhzOKgbEwWOxaBDKM
aLOPHd5lc/9nXmW8Sdh2nzMUZaF3lMktAgMBAAGjggF6MIIBdjAOBgNVHQ8BAf8E
BAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUK9BpR5R2Cf70a40uQKb3
R01/CF4wHwYDVR0jBBgwFoAUK9BpR5R2Cf70a40uQKb3R01/CF4wggERBgNVHSAE
ggEIMIIBBDCCAQAGCSqGSIb3Y2QFATCB8jAqBggrBgEFBQcCARYeaHR0cHM6Ly93
d3cuYXBwbGUuY29tL2FwcGxlY2EvMIHDBggrBgEFBQcCAjCBthqBs1JlbGlhbmNl
IG9uIHRoaXMgY2VydGlmaWNhdGUgYnkgYW55IHBhcnR5IGFzc3VtZXMgYWNjZXB0
YW5jZSBvZiB0aGUgdGhlbiBhcHBsaWNhYmxlIHN0YW5kYXJkIHRlcm1zIGFuZCBj
b25kaXRpb25zIG9mIHVzZSwgY2VydGlmaWNhdGUgcG9saWN5IGFuZCBjZXJ0aWZp
Y2F0aW9uIHByYWN0aWNlIHN0YXRlbWVudHMuMA0GCSqGSIb3DQEBBQUAA4IBAQBc
NplMLXi37Yyb3PN3m/J20ncwT8EfhYOFG5k9RzfyqZtAjizUsZAS2L70c5vu0mQP
y3lPNNiiPvl4/2vIB+x9OYOLUyDTOMSxv5pPCmv/K/xZpwUJfBdAVhEedNO3iyM7
R6PVbyTi69G3cN8PReEnyvFteO3ntRcXqNx+IjXKJdXZD9Zr1KIkIxH3oayPc4Fg
xhtbCS+SsvhESPBgOJ4V9T0mZyCKM2r3DYLP3uujL/lTaltkwGMzd/c6ByxW69oP
IQ7aunMZT7XZNn/Bh1XZp5m5MkL72NVxnn6hUrcbvZNCJBIqxw8dtk2cXmPIS4AX
UKqK1drk/NAJBzewdXUh
-----END CERTIFICATE-----
"""

a = argparse.ArgumentParser(description=__doc__.split('\n')[0])
a.add_argument('out')
a.add_argument('--type', required=True)
a.add_argument('--audience', required=True)
a.add_argument('--build', required=True)
a.add_argument('--size', type=int, default=0)
a.add_argument('--path', default='')
o = a.parse_args()

der = ssl.PEM_cert_to_DER_cert(APPLE_ROOT_PEM)
if hashlib.sha256(der).hexdigest() != APPLE_ROOT_SHA256:
    sys.exit('the embedded Apple Root CA is not the pinned one')
ctx = ssl.create_default_context(cadata=APPLE_ROOT_PEM)     # this root only; host name checked

body = {'AssetAudience': o.audience, 'AssetType': o.type, 'ClientVersion': 2, 'RequestedBuild': o.build,
        'ClientData': {'AllowXmlFallback': False, 'DeviceAccessClient': 'xcodebuild'}}
req = urllib.request.Request('https://gdmf.apple.com/v2/assets', json.dumps(body).encode(),
                             {'Content-Type': 'application/json', 'User-Agent': 'xcodebuild'})
try:
    raw = urllib.request.urlopen(req, context=ctx, timeout=60).read().decode()
except Exception as e:
    sys.exit(f'gdmf.apple.com: {e}')
# a JWS (header.payload.signature) whose payload is the JSON, or the JSON itself
parts = raw.split('.')
p = json.loads(base64.urlsafe_b64decode(parts[1] + '=' * (-len(parts[1]) % 4))) if len(parts) == 3 else json.loads(raw)
assets = p.get('Assets', [])
print(f'{o.type}: {len(assets)} asset(s): ' + ', '.join(f'{x.get("Build")} {x.get("_DownloadSize")}' for x in assets))
hit = [x for x in assets if x.get('Build') == o.build or x.get('SimulatorRuntimeBuildVersion') == o.build]
if len(hit) != 1:
    sys.exit(f'{len(hit)} assets of build {o.build} in the answer, expected 1')
x = hit[0]
url = x.get('__BaseURL', '') + x.get('__RelativePath', '')
if not url.startswith('https://') or not x.get('ArchiveDecryptionKey'):
    sys.exit(f'the asset has no https URL or no decryption key: {sorted(x)}')
if o.size and x.get('_DownloadSize') != o.size:
    sys.exit(f'the asset is {x.get("_DownloadSize")} bytes, not the pinned {o.size} (Apple changed it?)')
if o.path and x.get('__RelativePath') != o.path:
    sys.exit(f'the asset is {x.get("__RelativePath")}, not the pinned {o.path} (Apple changed it?)')
x['url'] = url
with open(o.out, 'w') as f:
    json.dump(x, f, indent=1)
print(f'{o.build}: {url} ({x.get("_DownloadSize")} bytes) -> {o.out}')
