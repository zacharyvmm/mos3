"""
basic_usage.mojo — Demonstrates core S3 operations: put, get, stat, delete, list.

Run against a local moto server:
  python3 -c "
import urllib.request, subprocess, os
from moto.server import ThreadedMotoServer
s = ThreadedMotoServer(port=15001)
s.start()
urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:15001/test-bucket', method='PUT'))
subprocess.run(['.venv/bin/mojo', 'run', '-I', '.', 'examples/basic_usage.mojo'], env={**os.environ, 'MOTO_PORT': '15001'})
s.stop()
"
"""
from std.os import getenv
from mos3_signing.credentials import S3Credentials
from mos3.client import S3Client


def _make_client() raises -> S3Client:
    """Create an S3Client pointed at a local moto server."""
    var port: String = "15001"
    var port_env = getenv("MOTO_PORT")
    if port_env:
        port = port_env

    var creds = S3Credentials.create(
        access_key_id="AKIAIOEXAMPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="127.0.0.1:" + port,
        bucket="test-bucket",
        virtual_hosted_style=False,
        insecure_http=True,
    )
    return S3Client.create(creds)


def main() raises:
    var client = _make_client()

    # ── Put ──────────────────────────────────────────────────────
    print("=== Put ===")
    var put_result = client.put(
        "hello.txt",
        "Hello from Mojo! This is a test object.",
        content_type="text/plain",
    )
    print("Uploaded 'hello.txt', ETag:", put_result.etag)

    # ── Get ──────────────────────────────────────────────────────
    print("\n=== Get ===")
    var get_result = client.get("hello.txt")
    print("Downloaded 'hello.txt':")
    print("  Body:", get_result.body)
    print("  ETag:", get_result.etag)

    # ── Stat ─────────────────────────────────────────────────────
    print("\n=== Stat ===")
    var stat_result = client.stat("hello.txt")
    print("Stat 'hello.txt':")
    print("  Size:", stat_result.size, "bytes")
    print("  ETag:", stat_result.etag)
    print("  Content-Type:", stat_result.content_type)
    print("  Last-Modified:", stat_result.last_modified)

    # ── List ─────────────────────────────────────────────────────
    print("\n=== List ===")
    # Upload a few more objects to list
    _ = client.put("photos/sunset.jpg", "fake image data")
    _ = client.put("photos/vacation.png", "fake png data")
    _ = client.put("docs/notes.txt", "meeting notes")

    var list_result = client.list_objects(prefix="photos/")
    print("Objects with prefix 'photos/':")
    print("  Count:", list_result.key_count)
    for item in list_result.contents:
        print("   -", item.key, "(" + String(item.size) + " bytes)")

    # List all objects
    var all_result = client.list_objects(max_keys=100)
    print("\nAll objects (max 100):")
    print("  Count:", all_result.key_count)
    for item in all_result.contents:
        print("   -", item.key)

    # ── Object exists ────────────────────────────────────────────
    print("\n=== Object Exists ===")
    var exists = client.object_exists("hello.txt")
    print("hello.txt exists:", exists)
    var not_exists = client.object_exists("nonexistent.txt")
    print("nonexistent.txt exists:", not_exists)

    # ── Head all headers ─────────────────────────────────────────
    print("\n=== Head Object ===")
    var headers = client.head_object("hello.txt")
    print("All headers for 'hello.txt':")
    for entry in headers.items():
        print("  " + entry.key + ": " + entry.value)

    # ── Delete ───────────────────────────────────────────────────
    print("\n=== Delete ===")
    _ = client.delete("hello.txt")
    print("Deleted 'hello.txt'")
    _ = client.delete("photos/sunset.jpg")
    _ = client.delete("photos/vacation.png")
    _ = client.delete("docs/notes.txt")
    print("Cleaned up all test objects")

    print("\n✅ basic_usage.mojo completed successfully!")
