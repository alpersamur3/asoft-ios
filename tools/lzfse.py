"""LZFSE decompression in plain Python (Apple's format, as in its reference lzfse_decode).

Enough for the firmware files of an IPSW (an IM4P's "bvx2" payload) on a PC with no lzfse
library: uncompressed and LZFSE v1/v2 blocks. LZVN blocks, which the encoder uses only for
inputs under 4 KB, are not handled.
    data = lzfse.decompress(blob)
"""
import struct

L_SYMBOLS, M_SYMBOLS, D_SYMBOLS, LITERAL_SYMBOLS = 20, 20, 64, 256
L_STATES, M_STATES, D_STATES, LITERAL_STATES = 64, 64, 256, 1024

L_EXTRA_BITS = [0] * 16 + [2, 3, 5, 8]
L_BASE = list(range(16)) + [16, 20, 28, 60]
M_EXTRA_BITS = [0] * 16 + [3, 5, 8, 11]
M_BASE = list(range(16)) + [16, 24, 56, 312]
D_EXTRA_BITS = [n for n in range(16) for _ in range(4)]
D_BASE = [0, 1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24, 28, 36, 44, 52,
          60, 76, 92, 108, 124, 156, 188, 220, 252, 316, 380, 444, 508, 636, 764, 892,
          1020, 1276, 1532, 1788, 2044, 2556, 3068, 3580, 4092, 5116, 6140, 7164,
          8188, 10236, 12284, 14332, 16380, 20476, 24572, 28668, 32764, 40956, 49148, 57340,
          65532, 81916, 98300, 114684, 131068, 163836, 196604, 229372]

# A v2 header's frequency table: a variable-length code read from the low 5 bits
FREQ_NBITS = [2, 3, 2, 5, 2, 3, 2, 8, 2, 3, 2, 5, 2, 3, 2, 14] * 2
FREQ_VALUE = [0, 2, 1, 4, 0, 3, 1, -1, 0, 2, 1, 5, 0, 3, 1, -1,
              0, 2, 1, 6, 0, 3, 1, -1, 0, 2, 1, 7, 0, 3, 1, -1]


class Error(ValueError):
    pass


def _field(v, offset, nbits):
    return (v >> offset) & ((1 << nbits) - 1)


def _v2_freqs(blob, pos, end):
    """The L, M, D and literal frequency tables packed in a v2 header."""
    freqs, accum, nbits = [], 0, 0
    for _ in range(L_SYMBOLS + M_SYMBOLS + D_SYMBOLS + LITERAL_SYMBOLS):
        while pos < end and nbits + 8 <= 32:
            accum |= blob[pos] << nbits
            nbits += 8
            pos += 1
        b = accum & 31
        n = FREQ_NBITS[b]
        value = 8 + ((accum >> 4) & 0xf) if n == 8 else 24 + ((accum >> 4) & 0x3ff) if n == 14 \
            else FREQ_VALUE[b]
        if n > nbits:
            raise Error('truncated frequency table')
        freqs.append(value)
        accum >>= n
        nbits -= n
    if nbits >= 8 or pos != end:
        raise Error('bad frequency table')
    return freqs


class _BackBits:
    """The bit stream a block's literals or L/M/D values are read from: backwards, from its
    end, as the reference decoder's 64-bit stream does. n (-7..0) is how many of the top bits
    of the last word are padding. Refills may read ahead of start, down to the blob's start
    (bits it never uses), as the reference's do."""

    def __init__(self, blob, start, end, n):
        size = 8 if n else 7
        self.p = end - size
        if self.p < start:
            raise Error('bit stream out of range')
        self.blob, self.start = blob, 0
        self.acc = int.from_bytes(blob[self.p:end], 'little')
        self.nbits = n + 64 if n else 56
        if not 56 <= self.nbits < 64 or self.acc >> self.nbits:
            raise Error('bad bit stream start')

    def flush(self):
        n = (63 - self.nbits) & ~7
        p = self.p - (n >> 3)
        if p < self.start:
            raise Error('bit stream out of range')
        incoming = int.from_bytes(self.blob[p:p + 8], 'little') & ((1 << n) - 1)
        self.acc = (self.acc << n) | incoming
        self.nbits += n
        self.p = p

    def pull(self, n):
        self.nbits -= n
        value = self.acc >> self.nbits
        self.acc &= (1 << self.nbits) - 1
        return value


def _decoder_table(nstates, freqs):
    """Literal states: (bits to read, symbol, next-state base) per state."""
    table, total = [], 0
    for symbol, f in enumerate(freqs):
        if not f:
            continue
        total += f
        if total > nstates:
            raise Error('bad frequencies')
        k = nstates.bit_length() - f.bit_length()
        j0 = ((2 * nstates) >> k) - f
        for j in range(f):
            if j < j0:
                table.append((k, symbol, ((f + j) << k) - nstates))
            else:
                table.append((k - 1, symbol, (j - j0) << (k - 1)))
    return table


def _value_table(nstates, freqs, extra_bits, base):
    """L, M or D states: (bits to read, value bits, next-state base, value base) per state."""
    table = []
    for symbol, f in enumerate(freqs):
        if not f:
            continue
        k = nstates.bit_length() - f.bit_length()
        j0 = ((2 * nstates) >> k) - f
        vbits = extra_bits[symbol]
        for j in range(f):
            if j < j0:
                table.append((k + vbits, vbits, ((f + j) << k) - nstates, base[symbol]))
            else:
                table.append((k - 1 + vbits, vbits, (j - j0) << (k - 1), base[symbol]))
    if len(table) != nstates:
        raise Error('bad frequencies')
    return table


def _value(table, state, bits):
    total, vbits, delta, vbase = table[state]
    v = bits.pull(total)
    return delta + (v >> vbits), vbase + (v & ((1 << vbits) - 1))


def _block(blob, pos, h, out):
    """One LZFSE block, its header h already read; pos is its literal payload. Returns the
    position after the block."""
    literal_table = _decoder_table(LITERAL_STATES, h['literal_freq'])
    l_table = _value_table(L_STATES, h['l_freq'], L_EXTRA_BITS, L_BASE)
    m_table = _value_table(M_STATES, h['m_freq'], M_EXTRA_BITS, M_BASE)
    d_table = _value_table(D_STATES, h['d_freq'], D_EXTRA_BITS, D_BASE)
    if len(literal_table) != LITERAL_STATES:
        raise Error('bad literal frequencies')

    lit_end = pos + h['n_literal_payload_bytes']
    bits = _BackBits(blob, 0, lit_end, h['literal_bits'])
    states = list(h['literal_state'])
    literals = bytearray()
    for _ in range(0, h['n_literals'], 4):
        bits.flush()
        for i in range(4):
            k, symbol, delta = literal_table[states[i]]
            states[i] = delta + bits.pull(k)
            literals.append(symbol)

    lmd_end = lit_end + h['n_lmd_payload_bytes']
    bits = _BackBits(blob, lit_end, lmd_end, h['lmd_bits'])
    l_state, m_state, d_state = h['l_state'], h['m_state'], h['d_state']
    lit, d = 0, -1
    for _ in range(h['n_matches']):
        bits.flush()
        l_state, length = _value(l_table, l_state, bits)
        m_state, match = _value(m_table, m_state, bits)
        d_state, new_d = _value(d_table, d_state, bits)
        d = new_d or d
        out += literals[lit:lit + length]
        lit += length
        if d <= 0 or d > len(out):
            if match:
                raise Error('match distance out of range')
        elif d >= match:
            out += out[len(out) - d:len(out) - d + match]
        else:
            for _ in range(match):
                out.append(out[-d])
    return lmd_end


def decompress(blob):
    out = bytearray()
    pos = 0
    while True:
        magic = blob[pos:pos + 4]
        if magic == b'bvx$':
            return bytes(out)
        if magic == b'bvx-':
            n, = struct.unpack_from('<I', blob, pos + 4)
            out += blob[pos + 8:pos + 8 + n]
            pos += 8 + n
        elif magic == b'bvx1':
            f = struct.unpack_from('<6I i 4H i 3H', blob, pos + 4)
            freqs = struct.unpack_from('<360H', blob, pos + 4 + 46)
            h = dict(n_raw_bytes=f[0], n_literals=f[2], n_matches=f[3],
                     n_literal_payload_bytes=f[4], n_lmd_payload_bytes=f[5],
                     literal_bits=f[6], literal_state=f[7:11], lmd_bits=f[11],
                     l_state=f[12], m_state=f[13], d_state=f[14])
            pos += 4 + 46 + 720
        elif magic == b'bvx2':
            n_raw, v0, v1, v2 = struct.unpack_from('<I3Q', blob, pos + 4)
            header_end = pos + _field(v2, 0, 32)
            freqs = _v2_freqs(blob, pos + 32, header_end)
            h = dict(n_raw_bytes=n_raw,
                     n_literals=_field(v0, 0, 20), n_literal_payload_bytes=_field(v0, 20, 20),
                     n_matches=_field(v0, 40, 20), literal_bits=_field(v0, 60, 3) - 7,
                     literal_state=[_field(v1, i, 10) for i in (0, 10, 20, 30)],
                     n_lmd_payload_bytes=_field(v1, 40, 20), lmd_bits=_field(v1, 60, 3) - 7,
                     l_state=_field(v2, 32, 10), m_state=_field(v2, 42, 10),
                     d_state=_field(v2, 52, 10))
            pos = header_end
        elif magic == b'bvxn':
            raise Error('LZVN block: not handled')
        else:
            raise Error(f'unknown block {magic!r} at {pos}')
        if magic in (b'bvx1', b'bvx2'):
            h['l_freq'] = freqs[:L_SYMBOLS]
            h['m_freq'] = freqs[L_SYMBOLS:L_SYMBOLS + M_SYMBOLS]
            h['d_freq'] = freqs[L_SYMBOLS + M_SYMBOLS:L_SYMBOLS + M_SYMBOLS + D_SYMBOLS]
            h['literal_freq'] = freqs[L_SYMBOLS + M_SYMBOLS + D_SYMBOLS:]
            start = len(out)
            pos = _block(blob, pos, h, out)
            if len(out) - start != h['n_raw_bytes']:
                raise Error('block size mismatch')
