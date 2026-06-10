"""
Pure Mojo SHA-256 implementation.
No Python dependencies — operates on raw bytes via Span[UInt8].

Based on FIPS 180-4. Processes messages of any size,
produces 32-byte (256-bit) digests.
"""


# Initial hash values (first 32 bits of fractional parts of square roots of primes 2..19)
comptime _H0: UInt32 = 0x6A09E667
comptime _H1: UInt32 = 0xBB67AE85
comptime _H2: UInt32 = 0x3C6EF372
comptime _H3: UInt32 = 0xA54FF53A
comptime _H4: UInt32 = 0x510E527F
comptime _H5: UInt32 = 0x9B05688C
comptime _H6: UInt32 = 0x1F83D9AB
comptime _H7: UInt32 = 0x5BE0CD19

# Round constants (first 32 bits of fractional parts of cube roots of primes 2..311)
comptime _K: InlineArray[UInt32, 64] = InlineArray[UInt32, 64](
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
    0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
    0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
    0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
    0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
    0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
    0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
    0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
    0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
)


@fieldwise_init
struct SHA256:
    """SHA-256 hash state. Feed data with update(), finalize with digest()."""
    var _h: InlineArray[UInt32, 8]
    var _len: UInt64
    var _buf: InlineArray[UInt8, 64]
    var _buf_len: Int

    def __init__(out self):
        self._h = InlineArray[UInt32, 8](
            _H0, _H1, _H2, _H3, _H4, _H5, _H6, _H7,
        )
        self._len = 0
        self._buf = InlineArray[UInt8, 64]()
        self._buf_len = 0

    def update(mut self, data: Span[UInt8]):
        """Feed bytes into the hash."""
        for i in range(len(data)):
            self._buf[self._buf_len] = data[i]
            self._buf_len += 1
            if self._buf_len == 64:
                self._process_chunk()
                self._buf_len = 0
        self._len += UInt64(len(data))

    def digest(mut self) -> InlineArray[UInt8, 32]:
        """Finalize and return the 32-byte digest."""
        # Padding: append 0x80, then zeros, then length in bits as big-endian UInt64
        var bit_len = self._len * 8

        # Append 0x80
        self._buf[self._buf_len] = 0x80
        self._buf_len += 1

        # If no room for length, pad with zeros and process
        if self._buf_len > 56:
            while self._buf_len < 64:
                self._buf[self._buf_len] = 0
                self._buf_len += 1
            self._process_chunk()
            self._buf_len = 0

        # Pad with zeros until 56 bytes
        while self._buf_len < 56:
            self._buf[self._buf_len] = 0
            self._buf_len += 1

        # Append bit length as big-endian UInt64 (8 bytes)
        for i in range(8):
            self._buf[56 + i] = UInt8((bit_len >> (56 - i * 8)) & 0xFF)

        self._process_chunk()

        # Convert hash words to bytes (big-endian)
        var result = InlineArray[UInt8, 32]()
        for i in range(8):
            var w = self._h[i]
            result[i * 4 + 0] = UInt8((w >> 24) & 0xFF)
            result[i * 4 + 1] = UInt8((w >> 16) & 0xFF)
            result[i * 4 + 2] = UInt8((w >> 8) & 0xFF)
            result[i * 4 + 3] = UInt8(w & 0xFF)

        return result

    # ── Internal ────────────────────────────────────────────────

    def _process_chunk(mut self):
        """Process a 64-byte chunk through SHA-256 compression function."""
        # Prepare message schedule w[0..63]
        var w = InlineArray[UInt32, 64]()

        for i in range(16):
            w[i] = (
                UInt32(self._buf[i * 4]) << 24
                | UInt32(self._buf[i * 4 + 1]) << 16
                | UInt32(self._buf[i * 4 + 2]) << 8
                | UInt32(self._buf[i * 4 + 3])
            )

        for i in range(16, 64):
            var s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            var s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] + s0 + w[i - 7] + s1

        var a = self._h[0]
        var b = self._h[1]
        var c = self._h[2]
        var d = self._h[3]
        var e = self._h[4]
        var f = self._h[5]
        var g = self._h[6]
        var h_val = self._h[7]

        for i in range(64):
            var S1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25)
            var ch = (e & f) ^ ((~e) & g)
            var temp1 = h_val + S1 + ch + _K[i] + w[i]
            var S0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22)
            var maj = (a & b) ^ (a & c) ^ (b & c)
            var temp2 = S0 + maj

            h_val = g
            g = f
            f = e
            e = d + temp1
            d = c
            c = b
            b = a
            a = temp1 + temp2

        self._h[0] += a
        self._h[1] += b
        self._h[2] += c
        self._h[3] += d
        self._h[4] += e
        self._h[5] += f
        self._h[6] += g
        self._h[7] += h_val


# ── Free functions ──────────────────────────────────────────────


@always_inline
def _rotr(x: UInt32, n: Int) -> UInt32:
    """Right-rotate a 32-bit word by n bits."""
    return (x >> n) | (x << (32 - n))


def sha256(data: String) -> String:
    """Compute SHA-256 hash of a string, return hex digest."""
    var sha = SHA256()
    sha.update(data.as_bytes())
    var digest = sha.digest()

    comptime HEX: String = "0123456789abcdef"
    var result = String("")
    for i in range(32):
        var b = Int(digest[i])
        result += String(HEX[byte=(b >> 4)], HEX[byte=(b & 0xF)])
    return result
