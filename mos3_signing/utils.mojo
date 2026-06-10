"""
URI encoding and hex utilities for AWS Signature V4.
Pure Mojo — no Python dependencies.
"""


def hex_encode(data: String) -> String:
    """Encode a byte string as lowercase hex."""
    comptime HEX_CHARS: String = "0123456789abcdef"
    var result = String("")
    var bytes = data.as_bytes()
    for i in range(len(bytes)):
        var b = Int(bytes[i])
        var high = HEX_CHARS[byte=(b >> 4)]
        var low = HEX_CHARS[byte=(b & 0xF)]
        result += high
        result += low
    return result


def _is_uri_unreserved(byte: UInt8) -> Bool:
    """Check if a byte is in the URI unreserved set (RFC 3986)."""
    var b = Int(byte)
    # A-Z, a-z, 0-9, -, ., _, ~
    return (
        (b >= 65 and b <= 90)
        or (b >= 97 and b <= 122)
        or (b >= 48 and b <= 57)
        or b == 45
        or b == 46
        or b == 95
        or b == 126
    )


def uri_encode(data: String, encode_slash: Bool = False) -> String:
    """
    Percent-encode a string for URI components.

    If encode_slash is False, '/' is preserved (path encoding).
    If encode_slash is True, '/' is encoded as '%2F' (query param encoding).
    """
    comptime HEX_CHARS: String = "0123456789ABCDEF"
    var result = String("")
    var bytes = data.as_bytes()
    for i in range(len(bytes)):
        var byte = bytes[i]
        if _is_uri_unreserved(byte) or (not encode_slash and byte == 0x2F):
            # Append the literal byte as a single-byte string
            result += String(data[byte=i])
        else:
            var b = Int(byte)
            var high = HEX_CHARS[byte=(b >> 4)]
            var low = HEX_CHARS[byte=(b & 0xF)]
            result += "%"
            result += high
            result += low
    return result
