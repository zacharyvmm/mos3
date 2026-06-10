"""
SHA-256 + HMAC-SHA256 for S3 signing.
SHA-256: pure Mojo (via crypto_sha256.mojo).
HMAC-SHA256: uses Python's hmac module (thin wrapper; called once per signature).
"""
from mos3_signing.crypto_sha256 import (
    SHA256,
    sha256,
    _rotr,
    _bytes_to_hex,
)

from std.python import Python, PythonObject


def hmac_sha256(key: String, data: String) raises -> String:
    """Compute HMAC-SHA256, return lowercase hex digest.
    
    Uses Python's hmac module internally. The Python call overhead
    is negligible since this is called once per signing operation.
    """
    var hashlib = Python.import_module("hashlib")
    var hmac = Python.import_module("hmac")
    var py_key = PythonObject(key).encode("utf-8")
    var py_data = PythonObject(data).encode("utf-8")
    var h = hmac.new(py_key, py_data, hashlib.sha256)
    return String(py=h.hexdigest())


def hmac_sha256_hex_key(key_hex: String, data: String) raises -> String:
    """Compute HMAC-SHA256 where the key is hex-encoded.
    
    Used in AWS Signature V4 key derivation chain.
    Decodes key_hex to raw bytes, then computes HMAC.
    """
    var hashlib = Python.import_module("hashlib")
    var hmac = Python.import_module("hmac")
    var raw_key = Python.evaluate("bytes.fromhex")(key_hex)
    var py_data = PythonObject(data).encode("utf-8")
    var h = hmac.new(raw_key, py_data, hashlib.sha256)
    return String(py=h.hexdigest())
