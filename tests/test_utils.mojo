from std.testing import assert_equal
from mos3_signing.utils import hex_encode, uri_encode


def test_hex_encode_empty() raises:
    assert_equal(hex_encode(""), "")


def test_hex_encode_hello() raises:
    # "hello" -> 68 65 6c 6c 6f
    assert_equal(hex_encode("hello"), "68656c6c6f")


def test_hex_encode_binary() raises:
    var result = hex_encode("\x00\xff")
    assert_equal(result, "00ff")


def test_uri_encode_simple() raises:
    assert_equal(uri_encode("hello"), "hello")


def test_uri_encode_space() raises:
    assert_equal(uri_encode("hello world"), "hello%20world")


def test_uri_encode_path() raises:
    assert_equal(uri_encode("a/b/c"), "a/b/c")


def test_uri_encode_path_with_encode_slash() raises:
    assert_equal(uri_encode("a/b/c", encode_slash=True), "a%2Fb%2Fc")


def test_uri_encode_special() raises:
    assert_equal(uri_encode("a+b=c"), "a%2Bb%3Dc")


def main() raises:
    test_hex_encode_empty()
    test_hex_encode_hello()
    test_hex_encode_binary()
    test_uri_encode_simple()
    test_uri_encode_space()
    test_uri_encode_path()
    test_uri_encode_path_with_encode_slash()
    test_uri_encode_special()
    print("All utils tests passed!")
