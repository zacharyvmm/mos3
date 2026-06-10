"""
Pure Mojo SHA-256 implementation.
No Python dependencies — compatible with AWS Signature V4.
Based on FIPS 180-4.
"""
# NOTE: This is the pure Mojo SHA256 core.
# HMAC-SHA256 lives in crypto.mojo and uses Python for correctness.

comptime _H0: UInt32 = 0x6A09E667
comptime _H1: UInt32 = 0xBB67AE85
comptime _H2: UInt32 = 0x3C6EF372
comptime _H3: UInt32 = 0xA54FF53A
comptime _H4: UInt32 = 0x510E527F
comptime _H5: UInt32 = 0x9B05688C
comptime _H6: UInt32 = 0x1F83D9AB
comptime _H7: UInt32 = 0x5BE0CD19

def _make_k() -> InlineArray[UInt32, 64]:
    var k = InlineArray[UInt32, 64](fill=0)
    k[0]=0x428A2F98;k[1]=0x71374491;k[2]=0xB5C0FBCF;k[3]=0xE9B5DBA5
    k[4]=0x3956C25B;k[5]=0x59F111F1;k[6]=0x923F82A4;k[7]=0xAB1C5ED5
    k[8]=0xD807AA98;k[9]=0x12835B01;k[10]=0x243185BE;k[11]=0x550C7DC3
    k[12]=0x72BE5D74;k[13]=0x80DEB1FE;k[14]=0x9BDC06A7;k[15]=0xC19BF174
    k[16]=0xE49B69C1;k[17]=0xEFBE4786;k[18]=0x0FC19DC6;k[19]=0x240CA1CC
    k[20]=0x2DE92C6F;k[21]=0x4A7484AA;k[22]=0x5CB0A9DC;k[23]=0x76F988DA
    k[24]=0x983E5152;k[25]=0xA831C66D;k[26]=0xB00327C8;k[27]=0xBF597FC7
    k[28]=0xC6E00BF3;k[29]=0xD5A79147;k[30]=0x06CA6351;k[31]=0x14292967
    k[32]=0x27B70A85;k[33]=0x2E1B2138;k[34]=0x4D2C6DFC;k[35]=0x53380D13
    k[36]=0x650A7354;k[37]=0x766A0ABB;k[38]=0x81C2C92E;k[39]=0x92722C85
    k[40]=0xA2BFE8A1;k[41]=0xA81A664B;k[42]=0xC24B8B70;k[43]=0xC76C51A3
    k[44]=0xD192E819;k[45]=0xD6990624;k[46]=0xF40E3585;k[47]=0x106AA070
    k[48]=0x19A4C116;k[49]=0x1E376C08;k[50]=0x2748774C;k[51]=0x34B0BCB5
    k[52]=0x391C0CB3;k[53]=0x4ED8AA4A;k[54]=0x5B9CCA4F;k[55]=0x682E6FF3
    k[56]=0x748F82EE;k[57]=0x78A5636F;k[58]=0x84C87814;k[59]=0x8CC70208
    k[60]=0x90BEFFFA;k[61]=0xA4506CEB;k[62]=0xBEF9A3F7;k[63]=0xC67178F2
    return k


@fieldwise_init
struct SHA256:
    var _h: InlineArray[UInt32, 8]
    var _k: InlineArray[UInt32, 64]
    var _len: UInt64
    var _buf: InlineArray[UInt8, 64]
    var _buf_len: Int

    def __init__(out self):
        self._h = InlineArray[UInt32, 8](fill=0)
        self._h[0]=_H0;self._h[1]=_H1;self._h[2]=_H2;self._h[3]=_H3
        self._h[4]=_H4;self._h[5]=_H5;self._h[6]=_H6;self._h[7]=_H7
        self._k = _make_k()
        self._len = 0
        self._buf = InlineArray[UInt8, 64](fill=0)
        self._buf_len = 0

    def update[origin: Origin](mut self, data: Span[Byte, origin]):
        for i in range(len(data)):
            self._buf[self._buf_len] = UInt8(Int(data[i]))
            self._buf_len += 1
            if self._buf_len == 64:
                self._process_chunk()
                self._buf_len = 0
        self._len += UInt64(len(data))

    def digest(mut self) -> InlineArray[UInt8, 32]:
        var bit_len = self._len * 8
        self._buf[self._buf_len] = 0x80
        self._buf_len += 1
        if self._buf_len > 56:
            while self._buf_len < 64:
                self._buf[self._buf_len] = 0
                self._buf_len += 1
            self._process_chunk()
            self._buf_len = 0
        while self._buf_len < 56:
            self._buf[self._buf_len] = 0
            self._buf_len += 1
        for i in range(8):
            var shift = UInt64(56 - i * 8)
            self._buf[56 + i] = UInt8((bit_len >> shift) & 0xFF)
        self._process_chunk()
        var result = InlineArray[UInt8, 32](fill=0)
        for i in range(8):
            var w = self._h[i]
            result[i*4+0] = UInt8((w >> 24) & 0xFF)
            result[i*4+1] = UInt8((w >> 16) & 0xFF)
            result[i*4+2] = UInt8((w >> 8) & 0xFF)
            result[i*4+3] = UInt8(w & 0xFF)
        return result

    def _process_chunk(mut self):
        var w = InlineArray[UInt32, 64](fill=0)
        for i in range(16):
            w[i] = (UInt32(self._buf[i*4]) << 24) | (UInt32(self._buf[i*4+1]) << 16) | (UInt32(self._buf[i*4+2]) << 8) | UInt32(self._buf[i*4+3])
        for i in range(16, 64):
            var s0 = _rotr(w[i-15], 7) ^ _rotr(w[i-15], 18) ^ (w[i-15] >> 3)
            var s1 = _rotr(w[i-2], 17) ^ _rotr(w[i-2], 19) ^ (w[i-2] >> 10)
            w[i] = w[i-16] + s0 + w[i-7] + s1
        var a=self._h[0];var b=self._h[1];var c=self._h[2];var d=self._h[3]
        var e=self._h[4];var f=self._h[5];var g=self._h[6];var hv=self._h[7]
        for i in range(64):
            var S1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25)
            var ch = (e & f) ^ ((~e) & g)
            var temp1 = hv + S1 + ch + self._k[i] + w[i]
            var S0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22)
            var maj = (a & b) ^ (a & c) ^ (b & c)
            var temp2 = S0 + maj
            hv=g;g=f;f=e;e=d+temp1;d=c;c=b;b=a;a=temp1+temp2
        self._h[0]+=a;self._h[1]+=b;self._h[2]+=c;self._h[3]+=d
        self._h[4]+=e;self._h[5]+=f;self._h[6]+=g;self._h[7]+=hv


@always_inline
def _rotr(x: UInt32, n: Int) -> UInt32:
    return (x >> UInt32(n)) | (x << UInt32(32 - n))


def sha256(data: String) -> String:
    var sha = SHA256()
    sha.update(data.as_bytes())
    return _bytes_to_hex(sha.digest())


def _bytes_to_hex(digest: InlineArray[UInt8, 32]) -> String:
    comptime HEX: String = "0123456789abcdef"
    var result = String("")
    for i in range(32):
        var b = Int(digest[i])
        result += String(HEX[byte=(b >> 4)], HEX[byte=(b & 0xF)])
    return result
