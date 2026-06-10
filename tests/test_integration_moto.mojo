"""Integration tests against moto S3 server."""
from std.testing import assert_equal, assert_true
from std.os import getenv
from mos3_signing.credentials import S3Credentials
from mos3.client import S3Client


def _make_client() raises -> S3Client:
    # Port is injected by the Python test runner via MOTO_PORT env var
    var port: String = "15001"
    var port_env = getenv("MOTO_PORT")
    if port_env:
        port = port_env  # Optional unwraps in boolean context

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
    _ = client.put("to-delete.txt", "delete me")
    _ = client.delete("to-delete.txt")
    print("Delete OK")


def test_list_objects() raises:
    var client = _make_client()
    _ = client.put("dir/a.txt", "a")
    _ = client.put("dir/b.txt", "b")
    var list_result = client.list_objects(prefix="dir/")
    assert_equal(list_result.key_count, 2)
    assert_equal(len(list_result.contents), 2)
    print("List OK, found", list_result.key_count, "objects")


def main() raises:
    test_put_and_get()
    test_stat()
    test_delete()
    test_list_objects()
    print("All moto integration tests passed!")
