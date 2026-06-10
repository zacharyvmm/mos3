"""
Multipart upload for S3 objects.
Implements the S3 multipart upload API: initiate, upload parts, complete, abort.
"""
from std.python import Python, PythonObject
from mos3_signing.credentials import S3Credentials, SignOptions
from mos3_signing.signing import sign_request, _sha256_hex
from mos3.client import _do_s3_request, _get_response_header, _get_status, _raise_http_error_obj


@fieldwise_init
struct PartInfo(Movable, Copyable, ImplicitlyCopyable):
    """Information about a successfully uploaded part."""
    var part_number: Int
    var etag: String


@fieldwise_init
struct MultipartUpload(Movable):
    """A multipart upload session. Parts are uploaded via upload_part(), then
    finalized with complete() or cancelled with abort()."""
    var credentials: S3Credentials
    var key: String
    var upload_id: String
    var _parts: List[PartInfo]

    @staticmethod
    def create(credentials: S3Credentials, key: String, content_type: String = "application/octet-stream") raises -> Self:
        """Initiate a multipart upload. Returns the upload session."""
        var response = _do_s3_request(
            credentials, key, "POST",
            body="",
            content_type=content_type,
            search_params="uploads",
        )
        var status = Int(py=_get_status(response))
        if status != 200:
            _raise_http_error_obj(response)
            raise Error(String("Failed to initiate multipart upload"))

        var body_bytes = response.read()
        var body = String(py=body_bytes.decode("utf-8"))
        var upload_id = _extract_xml_tag(body, "UploadId")
        if upload_id == "":
            raise Error(String("No UploadId in initiate response"))

        return Self(
            credentials=credentials,
            key=key,
            upload_id=upload_id,
            _parts=List[PartInfo](),
        )

    def upload_part(mut self, part_number: Int, data: String) raises -> PartInfo:
        """Upload a single part. Returns PartInfo with ETag for completion."""
        var search = "partNumber=" + String(part_number) + "&uploadId=" + self.upload_id
        var content_hash = _sha256_hex(data)

        var response = _do_s3_request(
            self.credentials, self.key, "PUT",
            body=data,
            content_hash=content_hash,
            search_params=search,
        )
        var status = Int(py=_get_status(response))
        if status != 200:
            _raise_http_error_obj(response)
            raise Error(String("Failed to upload part ", part_number))

        var etag = String(py=_get_response_header(response, "ETag", ""))
        var part = PartInfo(part_number=part_number, etag=etag)
        self._parts.append(part)
        return part

    def complete(self) raises -> Bool:
        """Complete the multipart upload. Returns True on success."""
        # Build the completion XML
        var xml = String('<CompleteMultipartUpload xmlns="http://s3.amazonaws.com/doc/2006-03-01/">')
        for i in range(len(self._parts)):
            var p = self._parts[i]
            xml += "<Part><PartNumber>" + String(p.part_number) + "</PartNumber>"
            xml += "<ETag>" + p.etag + "</ETag></Part>"
        xml += "</CompleteMultipartUpload>"

        var search = "uploadId=" + self.upload_id
        var content_hash = _sha256_hex(xml)

        var response = _do_s3_request(
            self.credentials, self.key, "POST",
            body=xml,
            content_hash=content_hash,
            content_type="application/xml",
            search_params=search,
        )
        var status = Int(py=_get_status(response))
        return status == 200

    def abort(self) raises -> Bool:
        """Abort the multipart upload. Returns True on success."""
        var search = "uploadId=" + self.upload_id
        var response = _do_s3_request(
            self.credentials, self.key, "DELETE",
            body="",
            search_params=search,
        )
        var status = Int(py=_get_status(response))
        return status == 204

    def upload_id_str(self) -> String:
        """Get the upload ID string."""
        return self.upload_id


def _extract_xml_tag(xml: String, tag: String) -> String:
    """Extract the content of an XML tag. Simple string-based parser."""
    var open_tag = "<" + tag + ">"
    var close_tag = "</" + tag + ">"

    var start = _find_str(xml, open_tag)
    if start < 0:
        return ""

    start += len(open_tag)
    var end = _find_str(xml, close_tag, start_pos=start)
    if end < 0:
        return ""

    var result = String("")
    var i = start
    while i < end:
        result += String(xml[byte=i])
        i += 1
    return result


def _find_str(haystack: String, needle: String, start_pos: Int = 0) -> Int:
    """Find a substring, return its index or -1."""
    var needle_len = needle.byte_length()
    var haystack_len = haystack.byte_length()
    if needle_len == 0:
        return start_pos

    var i = start_pos
    while i <= haystack_len - needle_len:
        var found = True
        var j = 0
        while j < needle_len:
            if haystack[byte=i + j] != needle[byte=j]:
                found = False
                break
            j += 1
        if found:
            return i
        i += 1
    return -1
