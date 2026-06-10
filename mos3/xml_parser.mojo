"""
S3 XML response parsing using Python's xml.etree.ElementTree.
Handles ListObjectsV2 results and S3 error responses.
"""
from std.python import Python, PythonObject
from mos3.types import ListObjectsV2Result, ListObjectsContents


def parse_list_objects_v2(xml_bytes: String) raises -> ListObjectsV2Result:
    """Parse an S3 ListObjectsV2 XML response into a Mojo struct."""
    var ET = Python.import_module("xml.etree.ElementTree")
    var root = ET.fromstring(xml_bytes)

    # Namespace (S3 uses this for ListBucketResult xmlns)
    var ns = "{http://s3.amazonaws.com/doc/2006-03-01/}"

    var result = ListObjectsV2Result(
        is_truncated=False,
        contents=List[ListObjectsContents](),
        name="",
        prefix="",
        max_keys=0,
        key_count=0,
        continuation_token="",
        next_continuation_token="",
        common_prefixes=List[String](),
        delimiter="",
    )

    result.name = _get_text(root, ns + "Name")
    result.prefix = _get_text(root, ns + "Prefix")
    result.max_keys = Int(py=_get_int(root, ns + "MaxKeys"))
    result.key_count = Int(py=_get_int(root, ns + "KeyCount"))
    result.delimiter = _get_text(root, ns + "Delimiter")
    result.is_truncated = _get_text(root, ns + "IsTruncated") == "true"
    result.continuation_token = _get_text(root, ns + "ContinuationToken")
    result.next_continuation_token = _get_text(root, ns + "NextContinuationToken")

    # Parse Contents
    for content_elem in root.iterfind(ns + "Contents"):
        var item = ListObjectsContents(
            key=_get_text(content_elem, ns + "Key"),
            etag=_get_text(content_elem, ns + "ETag"),
            size=Int(py=_get_int(content_elem, ns + "Size")),
            last_modified=_get_text(content_elem, ns + "LastModified"),
            storage_class=_get_text(content_elem, ns + "StorageClass"),
        )
        result.contents.append(item^)

    # Parse CommonPrefixes
    for prefix_elem in root.iterfind(ns + "CommonPrefixes"):
        var p = _get_text(prefix_elem, ns + "Prefix")
        if p != "":
            result.common_prefixes.append(p^)

    return result^


def _get_text(element: PythonObject, tag: String) raises -> String:
    """Get text content of a child element, or empty string if missing."""
    var child = element.find(tag)
    if child is None:
        return ""
    var text = child.text
    if text is None:
        return ""
    return String(py=text)


def _get_int(element: PythonObject, tag: String) raises -> PythonObject:
    """Get integer content of a child element, or 0 if missing."""
    var text = _get_text(element, tag)
    if text == "":
        return PythonObject(0)
    return PythonObject(Int(text))


def parse_s3_error(xml_bytes: String) raises -> Tuple[String, String]:
    """Parse an S3 error XML response, return (code, message)."""
    var ET = Python.import_module("xml.etree.ElementTree")
    var root = ET.fromstring(xml_bytes)

    var code = "UnknownError"
    var code_tag = root.find("Code")
    if code_tag is not None and code_tag.text is not None:
        code = String(py=code_tag.text)

    var message = "An unexpected error has occurred"
    var msg_tag = root.find("Message")
    if msg_tag is not None and msg_tag.text is not None:
        message = String(py=msg_tag.text)

    return (code, message)
