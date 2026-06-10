from std.testing import assert_equal
from mos3_signing.crypto_sha256 import sha256
from mos3_signing.crypto import hmac_sha256, hmac_sha256_hex_key


def test_sha256_empty() raises:
    assert_equal(sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")


def test_sha256_abc() raises:
    assert_equal(sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")


def test_sha256_hello_world() raises:
    assert_equal(sha256("hello world"), "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")


def test_sha256_fips_56bytes() raises:
    var data = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    assert_equal(sha256(data), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")


def test_hmac_sha256_rfc4231() raises:
    var key = "\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b"
    var h = hmac_sha256(key, "Hi There")
    assert_equal(h, "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")


def test_hmac_sha256_aws_chain() raises:
    var secret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    var k_date = hmac_sha256("AWS4" + secret, "20150830")
    assert_equal(k_date, "68a9e4535ffbb09dcb6d25807a9ba5e3aef7cd00b3c57ed4b0c4a04988649f51")


def test_hmac_sha256_hex_key() raises:
    # Test hex-key variant used in AWS chain
    var secret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    var k_date = hmac_sha256("AWS4" + secret, "20150830")
    # Step 2: kRegion = HMAC(kDate_raw, region) where kDate_raw = bytes.fromhex(k_date)
    var k_region = hmac_sha256_hex_key(k_date, "us-east-1")
    assert_equal(len(k_region), 64)


def main() raises:
    test_sha256_empty()
    test_sha256_abc()
    test_sha256_hello_world()
    test_sha256_fips_56bytes()
    test_hmac_sha256_rfc4231()
    test_hmac_sha256_aws_chain()
    test_hmac_sha256_hex_key()
    print("All crypto tests passed!")
