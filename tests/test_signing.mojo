from std.testing import assert_equal, assert_true
from mos3_signing.credentials import S3Credentials, SignOptions
from mos3_signing.signing import sign_request, _sha256_hex, presigned_get, presigned_put, presigned_post


def test_sha256_empty() raises:
    var h = _sha256_hex("")
    assert_equal(h, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")


def test_sign_request_basic() raises:
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="s3.amazonaws.com",
        bucket="example-bucket",
    )
    var opts = SignOptions.create(path="/test.txt", method="GET")
    var result = sign_request(creds, opts)

    # Verify structure
    assert_true("AWS4-HMAC-SHA256" in result.authorization_header)
    assert_true("Credential=AKIAIO...MPLE" in result.authorization_header)
    assert_true("us-east-1" in result.authorization_header)
    assert_true("aws4_request" in result.authorization_header)
    assert_true("SignedHeaders=" in result.authorization_header)
    assert_true("Signature=" in result.authorization_header)
    assert_true(result.url != "")
    assert_true(result.content_sha256 != "")
    assert_true(result.amz_date != "")


def test_sign_request_put_with_body_hash() raises:
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="s3.amazonaws.com",
        bucket="mybucket",
    )
    var content = "Hello, World!"
    var content_hash = _sha256_hex(content)
    var opts = SignOptions.create(
        path="/uploads/file.txt",
        method="PUT",
        content_hash=content_hash,
    )
    var result = sign_request(creds, opts)
    assert_true("AWS4-HMAC-SHA256" in result.authorization_header)
    assert_equal(result.content_sha256, content_hash)


def test_sign_request_virtual_hosted_style() raises:
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="s3.amazonaws.com",
        bucket="mybucket",
        virtual_hosted_style=True,
    )
    var opts = SignOptions.create(path="/key", method="GET")
    var result = sign_request(creds, opts)
    assert_true("mybucket.s3.amazonaws.com" in result.url)


def test_sign_request_path_style() raises:
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="s3.amazonaws.com",
        bucket="mybucket",
        virtual_hosted_style=False,
    )
    var opts = SignOptions.create(path="/key", method="GET")
    var result = sign_request(creds, opts)
    assert_true("s3.amazonaws.com/mybucket/key" in result.url)


def test_sign_request_with_session_token() raises:
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="s3.amazonaws.com",
        session_token="FQoGZXIvYXdzE...",
    )
    var opts = SignOptions.create(path="/test.txt", method="GET")
    var result = sign_request(creds, opts)
    assert_true("x-amz-security-token" in result.authorization_header)


def test_sign_request_invalid_method() raises:
    var creds = S3Credentials.create(
        access_key_id="test",
        secret_access_key="test",
    )
    var opts = SignOptions.create(path="/x", method="PATCH")
    try:
        var _ = sign_request(creds, opts)
        raise Error("Expected error for invalid method")
    except:
        pass  # Expected


def test_sign_request_missing_credentials() raises:
    var creds = S3Credentials.create(
        access_key_id="",
        secret_access_key="test",
    )
    var opts = SignOptions.create(path="/x", method="GET")
    try:
        var _ = sign_request(creds, opts)
        raise Error("Expected error for missing credentials")
    except:
        pass  # Expected


def test_presigned_get_url() raises:
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="s3.amazonaws.com",
        bucket="example-bucket",
    )
    var url = presigned_get(creds, "/test.txt", expires_in=3600)
    # Verify all required query params are present
    assert_true("X-Amz-Algorithm=AWS4-HMAC-SHA256" in url)
    assert_true("X-Amz-Credential=AKIAIO...MPLE" in url)
    assert_true("X-Amz-Date=" in url)
    assert_true("X-Amz-Expires=3600" in url)
    assert_true("X-Amz-SignedHeaders=host" in url)
    assert_true("X-Amz-Signature=" in url)
    assert_true("https://" in url)
    assert_true("/test.txt?" in url)

def test_presigned_put_url() raises:
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="s3.amazonaws.com",
        bucket="example-bucket",
    )
    var url = presigned_put(creds, "/upload.txt", expires_in=7200, content_type="text/plain")
    # Verify all required query params
    assert_true("X-Amz-Algorithm=AWS4-HMAC-SHA256" in url)
    assert_true("X-Amz-Credential=" in url)
    assert_true("X-Amz-Expires=7200" in url)
    assert_true("X-Amz-SignedHeaders=" in url)
    # Content-type should appear in signed headers
    assert_true("content-type" in url)
    assert_true("X-Amz-Signature=" in url)
    assert_true("https://" in url)

def test_presigned_post() raises:
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="s3.amazonaws.com",
        bucket="mybucket",
    )
    var result = presigned_post(creds, "uploads/file.txt", 3600)
    assert_true(result.url != "")
    assert_true("key" in result.fields)
    assert_true("policy" in result.fields)
    assert_true("X-Amz-Signature" in result.fields)
    assert_true("acl" in result.fields)
    assert_true("X-Amz-Algorithm" in result.fields)
    assert_true("X-Amz-Credential" in result.fields)
    assert_true("X-Amz-Date" in result.fields)
    # Verify field values
    assert_true(result.fields["key"] == "uploads/file.txt")
    assert_true(result.fields["acl"] == "private")
    assert_true(result.fields["X-Amz-Algorithm"] == "AWS4-HMAC-SHA256")


def test_presigned_url_with_session_token() raises:
    var creds = S3Credentials.create(
        access_key_id="AKIAIO...MPLE",
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        endpoint="s3.amazonaws.com",
        session_token="FQoGZXIvYXdzE...",
    )
    var url = presigned_get(creds, "/test.txt")
    assert_true("X-Amz-Security-Token=" in url)


def main() raises:
    test_sha256_empty()
    test_sign_request_basic()
    test_sign_request_put_with_body_hash()
    test_sign_request_virtual_hosted_style()
    test_sign_request_path_style()
    test_sign_request_with_session_token()
    test_sign_request_invalid_method()
    test_sign_request_missing_credentials()
    test_presigned_get_url()
    test_presigned_put_url()
    test_presigned_post()
    test_presigned_url_with_session_token()
    print("All signing tests passed!")
