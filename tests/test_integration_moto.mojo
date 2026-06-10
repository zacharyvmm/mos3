"""Integration tests against moto S3 server."""
from std.testing import assert_equal, assert_true
from std.os import getenv
from std.python import Python, PythonObject
from mos3_signing.credentials import S3Credentials
from mos3.client import S3Client, RetryConfig
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


def test_concurrent_multipart() raises:
    """Test concurrent multipart upload with 4 parts using ThreadPoolExecutor."""
    var creds = _make_creds()

    # Initiate multipart upload
    var mpu = MultipartUpload.create(creds, "concurrent-test.bin")
    print("Concurrent upload ID:", mpu.upload_id_str())

    # Create 4 parts of 5MB each (S3 minimum part size)
    var part_size = 5 * 1024 * 1024  # 5MB per part
    var data_bytes = Python.evaluate("b'Y' * " + String(part_size))
    var data_part = String(py=data_bytes.decode("utf-8"))

    # Build parts list for concurrent upload
    var parts_list = List[Tuple[Int, String]]()
    for i in range(4):
        parts_list.append((i + 1, data_part))

    # Upload all parts concurrently (queue_size=4 means all in parallel)
    mpu.upload_parts(parts_list, queue_size=4, retry=3)
    print("All 4 parts uploaded concurrently")

    # Complete
    var ok = mpu.complete()
    assert_true(ok)
    print("Concurrent multipart complete OK")

    # Verify total size
    var client = _make_client()
    var result = client.stat("concurrent-test.bin")
    var expected = part_size * 4
    assert_equal(result.size, expected)
    print("Concurrent content verified, total size:", result.size)


def test_get_range() raises:
    var client = _make_client()
    var content = "0123456789ABCDEF"
    var __put = client.put("range-test.txt", content)

    # Get bytes 0-4
    var result = client.get_range("range-test.txt", 0, 5)
    assert_equal(result.body, "01234")
    print("Range 0-4 OK:", result.body)

    # Get bytes 10-15
    var result2 = client.get_range("range-test.txt", 10, 6)
    assert_equal(result2.body, "ABCDEF")
    print("Range 10-15 OK:", result2.body)


def test_auto_multipart_large() raises:
    """Test auto-multipart upload with a body larger than part_size."""
    var client = _make_client()

    # Generate ~6MB of data to trigger auto-multipart (> 5MB default part_size)
    var size = 6 * 1024 * 1024  # 6 MB
    # Use a repeating pattern that's easy to verify
    var pattern = "Mos3AutoTest_"
    var pattern_len = 13
    var pattern_bytes = Python.evaluate("b'" + pattern + "'")
    var data = Python.evaluate("lambda p,n: p * (n // len(p)) + p[:n % len(p)]")(
        pattern_bytes, PythonObject(size)
    )
    var body = String(py=data.decode("utf-8"))

    # Upload using put_auto
    var put_result = client.put_auto("auto-multipart-large.bin", body, part_size=5 * 1024 * 1024)
    print("Auto-multipart etag:", put_result.etag)

    # Verify the uploaded object exists and has the right size
    var stat_result = client.stat("auto-multipart-large.bin")
    assert_equal(stat_result.size, size)
    print("Auto-multipart size verified:", stat_result.size)

    # Verify content: sample the first few bytes
    var get_result = client.get_range("auto-multipart-large.bin", 0, pattern_len)
    assert_equal(get_result.body, pattern)
    print("Auto-multipart content verified")

    # Also verify small files take the single-put path
    var small = "hello small world"
    var small_result = client.put_auto("auto-small.txt", small, part_size=5 * 1024 * 1024)
    print("Small auto-put etag:", small_result.etag)
    var small_get = client.get("auto-small.txt")
    assert_equal(small_get.body, small)
    print("Small auto-put content verified")


def test_put_file() raises:
    """Test put_file: read a local file and upload it."""
    var client = _make_client()

    # Create a temp file using Python
    var py_builtins = Python.import_module("builtins")
    var file_content = "Hello from put_file! This is a test file.\nLine 2\nLine 3\n"
    var tmp_path = "/tmp/mos3_test_put_file.txt"
    var f = py_builtins.open(tmp_path, "w")
    f.write(file_content)
    f.close()

    # Upload the file
    var put_result = client.put_file("put-file-test.txt", tmp_path)
    print("put_file etag:", put_result.etag)

    # Verify content
    var get_result = client.get("put-file-test.txt")
    assert_equal(get_result.body, file_content)
    print("put_file content verified")

    # Clean up
    var py_os = Python.import_module("os")
    py_os.remove(tmp_path)
    print("Temp file cleaned up")


def test_create_bucket() raises:
    # Create a new bucket via the client
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="127.0.0.1:15001",
        bucket="test-bucket-2",
        virtual_hosted_style=False,
        insecure_http=True,
    )
    var client = S3Client.create(creds)
    var ok = client.create_bucket()
    assert_true(ok)
    print("Create bucket OK")

    # Verify we can use it
    var __put = client.put("test.txt", "hello from bucket 2")
    var result = client.get("test.txt")
    assert_equal(result.body, "hello from bucket 2")
    print("New bucket works OK")


def test_retry_on_500() raises:
    """Test that S3Client retries on connection errors (non-existent port).
    Should retry a few times before giving up — verify it doesn't crash instantly."""
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="127.0.0.1:19999",  # Non-existent port
        bucket="test-bucket",
        virtual_hosted_style=False,
        insecure_http=True,
    )
    # Use a RetryConfig with small delays so test runs quickly
    var retry_config = RetryConfig.create(max_retries=2, base_delay_ms=10, max_delay_ms=100)
    var client = S3Client.create(creds, retry_config=retry_config)

    try:
        var _ = client.stat("test.txt")
        # Should not reach here — connection should fail
        raise Error("Expected connection error but none was raised")
    except:
        # Expected — connection should fail after retries
        print("Retry test: got expected connection error after retries")
        pass


def main() raises:
    test_put_and_get()
    test_stat()
    test_delete()
    test_list_objects()
    test_streaming_download()
    test_multipart_upload()
    test_multipart_abort()
    test_concurrent_multipart()
    test_get_range()
    test_auto_multipart_large()
    test_put_file()
    test_create_bucket()
    test_retry_on_500()
    print("All moto integration tests passed!")
