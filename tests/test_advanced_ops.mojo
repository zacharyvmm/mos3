"""Integration tests for advanced S3 operations against moto S3 server."""
from std.testing import assert_equal, assert_true, assert_false
from std.os import getenv
from std.python import Python, PythonObject
from std.collections import Dict
from mos3_signing.credentials import S3Credentials
from mos3.client import S3Client


def _make_client() raises -> S3Client:
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


def _make_creds_for_bucket(bucket: String) raises -> S3Credentials:
    var port: String = "15001"
    var port_env = getenv("MOTO_PORT")
    if port_env:
        port = port_env

    return S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="127.0.0.1:" + port,
        bucket=bucket,
        virtual_hosted_style=False,
        insecure_http=True,
    )


def test_copy_object() raises:
    """Test copying an object within the same bucket."""
    var client = _make_client()
    var __put = client.put("copy-src.txt", "copy me please")
    var ok = client.copy_object("copy-src.txt", "copy-dst.txt")
    assert_true(ok)
    var result = client.get("copy-dst.txt")
    assert_equal(result.body, "copy me please")
    print("Copy object OK")


def test_copy_object_cross_bucket() raises:
    """Test copying an object between buckets."""
    var src_client = _make_client()
    var __put = src_client.put("cross-src.txt", "cross-bucket copy")

    # Create destination bucket
    var dst_creds = _make_creds_for_bucket("test-bucket-copy")
    var dst_client = S3Client.create(dst_creds)
    var __created = dst_client.create_bucket()

    # Copy to different bucket
    var ok = src_client.copy_object("cross-src.txt", "cross-dst.txt", dst_bucket="test-bucket-copy")
    assert_true(ok)

    # Verify in destination bucket
    var result = dst_client.get("cross-dst.txt")
    assert_equal(result.body, "cross-bucket copy")
    print("Cross-bucket copy OK")


def test_put_with_metadata() raises:
    """Test uploading an object with custom metadata."""
    var client = _make_client()
    var metadata = Dict[String, String]()
    metadata["author"] = "test-user"
    metadata["version"] = "1.0"

    var put_result = client.put_with_metadata("meta-test.txt", "data with metadata", metadata)
    print("Put with metadata OK, etag:", put_result.etag)

    var headers = client.head_object("meta-test.txt")

    var found_author = False
    var found_version = False
    for entry in headers.items():
        var key_lower = String(py=PythonObject(entry.key).lower())
        if key_lower == "x-amz-meta-author":
            assert_equal(entry.value, "test-user")
            found_author = True
        if key_lower == "x-amz-meta-version":
            assert_equal(entry.value, "1.0")
            found_version = True

    assert_true(found_author)
    assert_true(found_version)
    print("Metadata headers verified OK")


def test_head_object() raises:
    """Test head_object returns all headers."""
    var client = _make_client()
    var __put = client.put("head-test.txt", "head me")

    var headers = client.head_object("head-test.txt")
    # Should at least have Content-Length
    var has_content_length = False
    for entry in headers.items():
        if entry.key == "Content-Length":
            has_content_length = True
            break
    assert_true(has_content_length)
    print("Head object OK, got", len(headers), "headers")


def test_head_object_missing() raises:
    """Test head_object on missing key raises error."""
    var client = _make_client()
    try:
        var headers = client.head_object("nonexistent-key-xyz")
        assert_false(True)  # Should not reach here
    except e:
        print("Head object missing correctly raised error:", e)


def test_object_exists() raises:
    """Test object_exists returns True for existing, False for missing."""
    var client = _make_client()
    var __put = client.put("exists-test.txt", "I exist")

    var yes = client.object_exists("exists-test.txt")
    assert_true(yes)

    var no = client.object_exists("does-not-exist.txt")
    assert_false(no)
    print("Object exists OK")


def test_bucket_exists() raises:
    """Test bucket_exists returns True for an existing bucket."""
    var client = _make_client()
    # Ensure bucket exists by putting an object first
    var __put = client.put("bucket-test.txt", "ensuring bucket exists")

    var exists = client.bucket_exists()
    assert_true(exists)
    print("Bucket exists OK")


def test_bucket_exists_missing() raises:
    """Test bucket_exists returns False for a non-existent bucket."""
    var creds = _make_creds_for_bucket("nonexistent-bucket-xyz")
    var client = S3Client.create(creds)

    var exists = client.bucket_exists()
    assert_false(exists)
    print("Bucket exists missing OK")


def main() raises:
    test_copy_object()
    test_copy_object_cross_bucket()
    test_put_with_metadata()
    test_head_object()
    test_head_object_missing()
    test_object_exists()
    test_bucket_exists()
    test_bucket_exists_missing()
    print("All advanced ops tests passed!")
