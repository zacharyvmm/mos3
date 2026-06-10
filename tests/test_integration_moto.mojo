"""Integration tests against moto S3 server."""
from std.testing import assert_equal, assert_true
from std.os import getenv
from std.python import Python, PythonObject
from mos3_signing.credentials import S3Credentials
from mos3.client import S3Client
from mos3.stream.download import DownloadStream
from mos3.stream.upload import MultipartUpload, PartInfo


def _make_client() raises -> S3Client:
    # Port is injected by the Python test runner via MOTO_PORT env var
    var port: String = "15001"
    var port_env = getenv("MOTO_PORT")
    if port_env:
        port = port_env

    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="127.0.0.1:" + port,
        bucket="test-bucket",
        virtual_hosted_style=False,
        insecure_http=True,
    )
    return S3Client.create(creds)


def _make_creds() raises -> S3Credentials:
    return S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="127.0.0.1:15001",
        bucket="test-bucket",
        virtual_hosted_style=False,
        insecure_http=True,
    )


def test_put_and_get() raises:
    var client = _make_client()
    var put_result = client.put("test.txt", "Hello, Moto!")
    print("Put OK, etag:", put_result.etag)
    var get_result = client.get("test.txt")
    assert_equal(get_result.body, "Hello, Moto!")


def test_stat() raises:
    var client = _make_client()
    var stat_result = client.stat("test.txt")
    assert_true(stat_result.size > 0)
    print("Stat OK, size:", stat_result.size)


def test_delete() raises:
    var client = _make_client()
    var __put = client.put("to-delete.txt", "delete me")
    _ = client.delete("to-delete.txt")
    print("Delete OK")


def test_list_objects() raises:
    var client = _make_client()
    var __put1 = client.put("dir/a.txt", "a")
    var __put2 = client.put("dir/b.txt", "b")
    var list_result = client.list_objects(prefix="dir/")
    assert_equal(list_result.key_count, 2)
    assert_equal(len(list_result.contents), 2)
    print("List OK, found", list_result.key_count, "objects")


def test_streaming_download() raises:
    var client = _make_client()
    var content = String("Chunk1: ")
    for _ in range(25):
        content += "x"
    content += "\nChunk2: "
    for _ in range(25):
        content += "y"
    content += "\nChunk3: end"
    var __put = client.put("stream-test.txt", content)

    var creds = _make_creds()
    var stream = DownloadStream.create(creds, "stream-test.txt", chunk_size=50)
    print("Stream ETag:", stream.etag())

    var received = String("")
    var chunks_read: Int = 0
    while True:
        var chunk = stream.read_chunk()
        if chunk == "":
            break
        received += chunk
        chunks_read += 1

    assert_true(chunks_read > 1)
    assert_equal(received, content)
    print("Streaming download OK, chunks:", chunks_read)


def test_multipart_upload() raises:
    var creds = _make_creds()

    # Initiate multipart upload
    var mpu = MultipartUpload.create(creds, "multipart-test.bin")
    print("Upload ID:", mpu.upload_id_str())

    # S3 requires parts to be at least 5MB. Use Python to generate efficiently.
    var part_size = 5 * 1024 * 1024  # 5MB per part (S3 minimum)
    var data_bytes = Python.evaluate("b'X' * " + String(part_size))
    var data_part = String(py=data_bytes.decode("utf-8"))

    var __p1 = mpu.upload_part(1, data_part)
    var __p2 = mpu.upload_part(2, data_part)
    print("Parts uploaded: 2 x 5MB")

    # Complete
    var ok = mpu.complete()
    assert_true(ok)
    print("Multipart complete OK")

    # Verify total size
    var client = _make_client()
    var result = client.stat("multipart-test.bin")
    var expected = 5 * 1024 * 1024 * 2
    assert_equal(result.size, expected)
    print("Multipart content verified, total size:", result.size)


def test_multipart_abort() raises:
    var creds = _make_creds()
    var mpu = MultipartUpload.create(creds, "abort-test.bin")
    var __p1 = mpu.upload_part(1, "data")
    var ok = mpu.abort()
    assert_true(ok)
    print("Multipart abort OK")


def main() raises:
    test_put_and_get()
    test_stat()
    test_delete()
    test_list_objects()
    test_streaming_download()
    test_multipart_upload()
    test_multipart_abort()
    print("All moto integration tests passed!")
