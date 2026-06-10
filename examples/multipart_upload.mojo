"""
multipart_upload.mojo — Demonstrates multipart upload for large objects.

Shows three approaches:
  1. Sequential multipart (upload_part one by one)
  2. Concurrent multipart (upload_parts with ThreadPoolExecutor)
  3. Auto-multipart (put_auto automatically uses multipart for large bodies)

Run against a local moto server:
  python3 -c "
import urllib.request, subprocess, os
from moto.server import ThreadedMotoServer
s = ThreadedMotoServer(port=15001)
s.start()
urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:15001/test-bucket', method='PUT'))
subprocess.run(['.venv/bin/mojo', 'run', '-I', '.', 'examples/multipart_upload.mojo'], env={**os.environ, 'MOTO_PORT': '15001'})
s.stop()
"
"""
from std.os import getenv
from std.python import Python, PythonObject
from mos3_signing.credentials import S3Credentials
from mos3.client import S3Client
from mos3.stream.upload import MultipartUpload, PartInfo


def _make_creds() raises -> S3Credentials:
    """Create credentials for the local moto server."""
    var port: String = "15001"
    var port_env = getenv("MOTO_PORT")
    if port_env:
        port = port_env

    return S3Credentials.create(
        access_key_id="AKIAIOEXAMPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="127.0.0.1:" + port,
        bucket="test-bucket",
        virtual_hosted_style=False,
        insecure_http=True,
    )


def main() raises:
    print("=== Multipart Upload ===\n")

    var creds = _make_creds()
    var client = S3Client.create(creds)

    # ── 1. Sequential Multipart ──────────────────────────────────
    print("--- 1. Sequential Multipart ---")

    # S3 requires parts to be at least 5MB. Generate 5MB of data per part.
    var part_size = 5 * 1024 * 1024  # 5MB per part
    var data_bytes = Python.evaluate("b'X' * " + str(part_size))
    var data_part1 = String(py=data_bytes.decode("utf-8"))

    # Different data for part 2 to verify integrity
    var data_part2_bytes = Python.evaluate("b'Y' * " + str(part_size))
    var data_part2 = String(py=data_part2_bytes.decode("utf-8"))

    # Initiate multipart upload
    var mpu = MultipartUpload.create(creds, "sequential-upload.bin")
    print("Upload ID:", mpu.upload_id_str())

    # Upload parts sequentially
    var part1_info = mpu.upload_part(1, data_part1)
    print("Part 1 uploaded, ETag:", part1_info.etag)

    var part2_info = mpu.upload_part(2, data_part2)
    print("Part 2 uploaded, ETag:", part2_info.etag)

    # Complete the upload
    var ok = mpu.complete()
    print("Completed:", ok)

    # Verify
    var stat_result = client.stat("sequential-upload.bin")
    print("Verified size:", stat_result.size, "bytes (expected", part_size * 2, ")")

    # ── 2. Concurrent Multipart ──────────────────────────────────
    print("\n--- 2. Concurrent Multipart ---")

    # Create 4 parts of 5MB each
    var concurrent_data = Python.evaluate("b'Z' * " + str(part_size))
    var concurrent_str = String(py=concurrent_data.decode("utf-8"))

    var mpu2 = MultipartUpload.create(creds, "concurrent-upload.bin")
    print("Upload ID:", mpu2.upload_id_str())

    # Build parts list for concurrent upload
    var parts_list = List[Tuple[Int, String]]()
    for i in range(4):
        parts_list.append((i + 1, concurrent_str))

    # Upload all parts concurrently (queue_size=4 means all in parallel)
    mpu2.upload_parts(parts_list, queue_size=4, retry=3)
    print("All 4 parts uploaded concurrently")

    var ok2 = mpu2.complete()
    print("Completed:", ok2)

    # Verify
    var stat2 = client.stat("concurrent-upload.bin")
    print("Verified size:", stat2.size, "bytes (expected", part_size * 4, ")")

    # ── 3. Auto-Multipart ────────────────────────────────────────
    print("\n--- 3. Auto-Multipart (put_auto) ---")

    # put_auto automatically uses multipart for bodies larger than part_size
    # Generate ~6MB of data to trigger auto-multipart (> 5MB default threshold)
    var auto_size = 6 * 1024 * 1024  # 6 MB
    var pattern = "Mos3Auto_"
    var auto_bytes = Python.evaluate(
        "lambda p,n: p * (n // len(p)) + p[:n % len(p)]"
    )(Python.evaluate("b'" + pattern + "'"), PythonObject(auto_size))
    var auto_body = String(py=auto_bytes.decode("utf-8"))

    print("Uploading", auto_size, "bytes via put_auto...")
    var auto_result = client.put_auto(
        "auto-upload.bin",
        auto_body,
        part_size=part_size,
    )
    print("ETag:", auto_result.etag)

    # Verify
    var auto_stat = client.stat("auto-upload.bin")
    print("Verified size:", auto_stat.size, "bytes (expected", auto_size, ")")

    # ── 4. Multipart Abort ───────────────────────────────────────
    print("\n--- 4. Multipart Abort ---")
    var mpu3 = MultipartUpload.create(creds, "to-be-aborted.bin")
    _ = mpu3.upload_part(1, "some small data")
    var aborted = mpu3.abort()
    print("Aborted:", aborted)
    print("(Aborted uploads don't create objects)")

    # Clean up
    _ = client.delete("sequential-upload.bin")
    _ = client.delete("concurrent-upload.bin")
    _ = client.delete("auto-upload.bin")

    print("\n✅ multipart_upload.mojo completed successfully!")
