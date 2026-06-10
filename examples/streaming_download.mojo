"""
streaming_download.mojo — Demonstrates streaming download in configurable chunks.

Uses DownloadStream to read an S3 object chunk by chunk, suitable for
large files where you don't want to buffer the entire body in memory.

Run against a local moto server:
  python3 -c "
import urllib.request, subprocess, os
from moto.server import ThreadedMotoServer
s = ThreadedMotoServer(port=15001)
s.start()
urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:15001/test-bucket', method='PUT'))
subprocess.run(['.venv/bin/mojo', 'run', '-I', '.', 'examples/streaming_download.mojo'], env={**os.environ, 'MOTO_PORT': '15001'})
s.stop()
"
"""
from std.os import getenv
from mos3_signing.credentials import S3Credentials
from mos3.client import S3Client
from mos3.stream.download import DownloadStream


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
    print("=== Streaming Download ===\n")

    var creds = _make_creds()

    # ── Setup: upload a multi-chunk test object ──────────────────
    var client = S3Client.create(creds)

    # Build a test file with distinct sections so we can see chunk boundaries
    var content = String("")
    content += "=== HEADER ===\n"
    for _ in range(40):
        content += "ABCDEFGHIJ"  # 10 bytes each × 40 = 400 bytes
    content += "\n=== BODY ===\n"
    for _ in range(60):
        content += "0123456789"  # 10 bytes each × 60 = 600 bytes
    content += "\n=== FOOTER ===\n"
    for _ in range(20):
        content += "ZYXWVUTSRQ"  # 10 bytes each × 20 = 200 bytes
    content += "\n"

    var total_size = content.byte_length()
    print("Uploading test object of", total_size, "bytes...")
    _ = client.put("stream-test.txt", content)
    print("Uploaded!\n")

    # ── 1. Streaming with small chunks (50 bytes) ────────────────
    print("--- 1. Small chunks (50 bytes) ---")

    var stream1 = DownloadStream.create(creds, "stream-test.txt", chunk_size=50)
    print("ETag:", stream1.etag())

    var received1 = String("")
    var chunk_count1: Int = 0
    while True:
        var chunk = stream1.read_chunk()
        if chunk == "":
            break
        received1 += chunk
        chunk_count1 += 1
        # Print first few bytes of each chunk to see boundaries
        var preview = chunk
        if preview.byte_length() > 30:
            preview = String("")
            var i: Int = 0
            while i < 30:
                preview += String(chunk[byte=i])
                i += 1
            preview += "..."
        print("  Chunk", chunk_count1, "(" + String(chunk.byte_length()) + " bytes):", preview)

    stream1.close()
    print("Total chunks:", chunk_count1)
    print("Received:", received1.byte_length(), "bytes (expected", total_size, ")")
    # Verify integrity
    if received1 == content:
        print("Content matches!")

    # ── 2. Streaming with larger chunks (256 bytes) ──────────────
    print("\n--- 2. Larger chunks (256 bytes) ---")

    var stream2 = DownloadStream.create(creds, "stream-test.txt", chunk_size=256)

    var received2 = String("")
    var chunk_count2: Int = 0
    while True:
        var chunk = stream2.read_chunk()
        if chunk == "":
            break
        received2 += chunk
        chunk_count2 += 1

    stream2.close()
    print("Chunks:", chunk_count2)
    print("Received:", received2.byte_length(), "bytes")
    if received2 == content:
        print("Content matches!")

    # ── 3. Read all at once ──────────────────────────────────────
    print("\n--- 3. read_all() convenience method ---")

    var stream3 = DownloadStream.create(creds, "stream-test.txt", chunk_size=512)
    var all_content = stream3.read_all()
    stream3.close()

    print("read_all():", all_content.byte_length(), "bytes")
    if all_content == content:
        print("Content matches!")

    print("""
How it works:
  - DownloadStream creates a streaming HTTP connection via Python's urllib
  - read_chunk() reads chunk_size bytes at a time from the response
  - Returns empty string when the stream is exhausted
  - close() releases the underlying TCP connection
  - Useful for large files: you process chunks as they arrive
    without buffering the entire file in memory
""")

    # Clean up
    _ = client.delete("stream-test.txt")

    print("✅ streaming_download.mojo completed successfully!")
