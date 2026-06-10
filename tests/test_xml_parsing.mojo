from std.testing import assert_equal
from mos3.xml_parser import parse_list_objects_v2, parse_s3_error


def test_parse_error_response() raises:
    var xml = """<?xml version="1.0" encoding="UTF-8"?>
<Error>
  <Code>NoSuchKey</Code>
  <Message>The specified key does not exist.</Message>
  <Key>test.txt</Key>
</Error>"""
    var (code, message) = parse_s3_error(xml)
    assert_equal(code, "NoSuchKey")
    assert_equal(message, "The specified key does not exist.")


def test_parse_list_objects_v2() raises:
    var xml = """<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>example-bucket</Name>
  <Prefix>photos/</Prefix>
  <KeyCount>2</KeyCount>
  <MaxKeys>1000</MaxKeys>
  <IsTruncated>false</IsTruncated>
  <Contents>
    <Key>photos/2006/January/sample.jpg</Key>
    <LastModified>2006-01-05T10:17:50.000Z</LastModified>
    <ETag>"d41d8cd98f00b204e9800998ecf8427e"</ETag>
    <Size>177432</Size>
    <StorageClass>STANDARD</StorageClass>
  </Contents>
  <Contents>
    <Key>photos/2006/February/sample.jpg</Key>
    <LastModified>2006-02-05T10:17:50.000Z</LastModified>
    <ETag>"e99a18c428cb38d5f260853678922e03"</ETag>
    <Size>204800</Size>
    <StorageClass>STANDARD</StorageClass>
  </Contents>
</ListBucketResult>"""
    var result = parse_list_objects_v2(xml)
    assert_equal(result.name, "example-bucket")
    assert_equal(result.prefix, "photos/")
    assert_equal(result.key_count, 2)
    assert_equal(result.is_truncated, False)
    assert_equal(len(result.contents), 2)
    assert_equal(result.contents[0].key, "photos/2006/January/sample.jpg")
    assert_equal(result.contents[0].size, 177432)
    assert_equal(result.contents[1].key, "photos/2006/February/sample.jpg")


def test_parse_list_objects_empty() raises:
    var xml = """<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>empty-bucket</Name>
  <KeyCount>0</KeyCount>
  <MaxKeys>1000</MaxKeys>
  <IsTruncated>false</IsTruncated>
</ListBucketResult>"""
    var result = parse_list_objects_v2(xml)
    assert_equal(result.name, "empty-bucket")
    assert_equal(result.key_count, 0)
    assert_equal(len(result.contents), 0)


def main() raises:
    test_parse_error_response()
    test_parse_list_objects_v2()
    test_parse_list_objects_empty()
    print("All XML parser tests passed!")
