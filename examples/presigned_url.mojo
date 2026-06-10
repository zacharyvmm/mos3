"""
presigned_url.mojo — Demonstrates presigned GET and PUT URL generation and usage.

Run against a local moto server:
  python3 -c "
import urllib.request, subprocess, os
from moto.server import ThreadedMotoServer
s = ThreadedMotoServer(port=15001)
s.start()
urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:15001/test-bucket', method='PUT'))
subprocess.run(['.venv/bin/mojo', 'run', '-I', '.', 'examples/presigned_url.mojo'], env={**os.environ, 'MOTO_PORT': '15001'})
s.stop()
"
"""
from std.os import getenv
from std.python import Python, PythonObject
from mos3_signing.credentials import S3Credentials
from mos3_signing.signing import presigned_get, presigned_put
from mos3.client import S3Client


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
    print("=== Presigned URLs ===\n")

    # ── Presigned GET ────────────────────────────────────────────
    print("--- Presigned GET ---")

    # First upload an object via the client
    var creds = _make_creds()
    var client = S3Client.create(creds)
    _ = client.put("presigned-test.txt", "Content accessed via presigned URL!")

    # Generate a presigned GET URL (valid for 1 hour)
    var get_url = presigned_get(creds, "presigned-test.txt", expires_in=3600)
    print("Presigned GET URL:")
    print(get_url)
    print()

    # Use the presigned URL via Python's urllib
    var urllib = Python.import_module("urllib.request")
    var req = urllib.Request(get_url, method="GET")
    var response = urllib.urlopen(req)
    var body = String(py=response.read().decode("utf-8"))
    print("Downloaded via presigned URL:")
    print("  Body:", body)
    print("  Status:", Int(py=response.getcode()))
    print()

    # ── Presigned PUT ────────────────────────────────────────────
    print("--- Presigned PUT ---")

    # Generate a presigned PUT URL (valid for 2 hours, with content type)
    var put_url = presigned_put(
        creds,
        "uploaded-via-presigned.txt",
        expires_in=7200,
        content_type="text/plain",
    )
    print("Presigned PUT URL:")
    print(put_url)
    print()

    # Upload via the presigned URL
    var upload_data_str = PythonObject("Uploaded via presigned PUT URL!")
    var upload_data = upload_data_str.encode("utf-8")
    var put_req = urllib.Request(put_url, data=upload_data, method="PUT")
    put_req.add_header("Content-Type", "text/plain")
    var put_response = urllib.urlopen(put_req)
    print("Upload via presigned URL, status:", Int(py=put_response.getcode()))

    # Verify via normal client get
    var get_result = client.get("uploaded-via-presigned.txt")
    print("Verified content:", get_result.body)

    # ── Short expiration ─────────────────────────────────────────
    print("\n--- Short expiration ---")
    var short_url = presigned_get(creds, "presigned-test.txt", expires_in=1)
    print("Presigned URL valid for 1 second:")
    print(short_url)
    print("(The URL should work immediately but expire quickly)")

    # Clean up
    _ = client.delete("presigned-test.txt")
    _ = client.delete("uploaded-via-presigned.txt")

    print("\n✅ presigned_url.mojo completed successfully!")
