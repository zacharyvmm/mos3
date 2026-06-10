from mos3_signing import S3Credentials, SignOptions, SignResult
from std.testing import assert_equal


def test_credentials_create() raises:
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="secret",
        region="us-east-1",
        endpoint="s3.amazonaws.com",
        bucket="my-bucket",
    )
    assert_equal(creds.access_key_id, "AKIAIO...MPLE")
    assert_equal(creds.region, "us-east-1")
    assert_equal(creds.bucket, "my-bucket")
    assert_equal(creds.virtual_hosted_style, True)
    assert_equal(creds.insecure_http, False)


def test_credentials_defaults() raises:
    var creds = S3Credentials.create(
        access_key_id="key",
        secret_access_key="secret",
    )
    assert_equal(creds.region, "us-east-1")
    assert_equal(creds.endpoint, "s3.amazonaws.com")
    assert_equal(creds.session_token, "")


def test_sign_options_create() raises:
    var opts = SignOptions.create(
        path="/test.txt",
        method="GET",
    )
    assert_equal(opts.path, "/test.txt")
    assert_equal(opts.method, "GET")
    assert_equal(opts.request_payer, False)


def main() raises:
    test_credentials_create()
    test_credentials_defaults()
    test_sign_options_create()
    print("All credentials tests passed!")
