from std.testing import assert_equal
from mos3_signing.error import S3Error, get_sign_error_message


def test_s3_error_default() raises:
    var err = S3Error()
    assert_equal(err.code, "UnknownError")
    assert_equal(err.message, "An unexpected error has occurred")


def test_s3_error_fieldwise() raises:
    var err = S3Error(code="NoSuchKey", message="The specified key does not exist.")
    assert_equal(err.code, "NoSuchKey")
    assert_equal(err.message, "The specified key does not exist.")


def test_get_sign_error_message_known() raises:
    assert_equal(
        get_sign_error_message("MissingCredentials"),
        "Missing required S3 credentials",
    )
    assert_equal(
        get_sign_error_message("InvalidMethod"),
        "Invalid HTTP method for S3 request",
    )


def test_get_sign_error_message_unknown() raises:
    assert_equal(get_sign_error_message("UnknownCode"), "Unknown signing error")


def main() raises:
    test_s3_error_default()
    test_s3_error_fieldwise()
    test_get_sign_error_message_known()
    test_get_sign_error_message_unknown()
    print("All error tests passed!")
