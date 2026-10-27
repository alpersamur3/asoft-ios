"""Patch mobileactivationd so -[DeviceType should_hactivate] answers YES (the guest
activates itself; vphone-cli's CustomFirmwareMobileActivation): the synthesised
getter `ldrb w0, [x0, #0x14] ; ret` at file offset 0x2c0dec of the 23G90 binary
becomes `mov x0, #1 ; ret`. The expected bytes are checked first.

    hact_patch.py ORIGINAL OUT
"""
import sys

OFF = 0x2c0dec
GETTER = bytes.fromhex("00504039c0035fd6")	# ldrb w0, [x0, #0x14] ; ret
YES = bytes.fromhex("200080d2c0035fd6")	# mov x0, #1 ; ret

d = bytearray(open(sys.argv[1], "rb").read())
if d[OFF:OFF + 8] != GETTER:
    raise SystemExit(f"unexpected bytes at {OFF:#x}: {d[OFF:OFF + 8].hex()}")
d[OFF:OFF + 8] = YES
open(sys.argv[2], "wb").write(d)
print(f"{sys.argv[2]}: should_hactivate -> YES at {OFF:#x}")
