"""
Benchmark helper for mos3 multipart upload.
Called via subprocess from tests/benchmark.py.

Prints machine-readable timing line: BENCH_MS: <milliseconds>

Environment variables:
  MOTO_PORT      — moto server port (default 15002)
  BENCH_KEY      — S3 key to upload (default "bench-multipart.bin")
  NUM_PARTS      — number of parts (default 3)
  PART_SIZE_MB   — size of each part in MB (default 5)
"""
from std.os import getenv
from std.python import Python, PythonObject

from mos3_signing.credentials import S3Credentials
from mos3.stream.upload import MultipartUpload


fn _get_env_or(name: String, default: String) -> String:
    var val = getenv(name)
    if val:
        return val
    return default


fn _parse_int(s: String, fallback: Int) -> Int:
    try:
        return Int(String(py=PythonObject(s)))
    except:
        return fallback


fn main() raises:
    var port = _get_env_or("MOTO_PORT", "15002")
    var key = _get_env_or("BENCH_KEY", "bench-multipart.bin")
    var num_parts = _parse_int(_get_env_or("NUM_PARTS", "3"), 3)
    var part_size_mb = _parse_int(_get_env_or("PART_SIZE_MB", "5"), 5)

    var part_size = part_size_mb * 1024 * 1024

    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="127.0.0.1:" + port,
        bucket="benchmark-bucket",
        virtual_hosted_style=False,
        insecure_http=True,
    )

    # Generate part data
    var data_bytes = Python.evaluate("b'X' * " + String(part_size))
    var data_str = String(py=data_bytes.decode("utf-8"))

    # Time the multipart upload using Python time (high precision)
    var py_time = Python.import_module("time")
    var t_start = py_time.perf_counter()

    var mpu = MultipartUpload.create(creds, key)

    for i in range(num_parts):
        var __ = mpu.upload_part(i + 1, data_str)

    var ok = mpu.complete()
    var t_end = py_time.perf_counter()

    if not ok:
        raise Error("Multipart upload failed to complete")

    var elapsed_ms = Int(py=((t_end - t_start) * 1000))

    # Print machine-readable result for parsing by benchmark.py
    print("BENCH_MS:", elapsed_ms)
