"""
S3Client — the main entry point for S3 operations.
Uses Python stdlib http.client for HTTP transport (no extra deps).
"""
from std.python import Python, PythonObject
from mos3_signing.credentials import S3Credentials, SignOptions, SignResult
from mos3_signing.signing import sign_request, _sha256_hex
from mos3_signing.error import S3Error
from mos3.types import StatSuccess, GetSuccess, PutSuccess, DeleteSuccess, ListObjectsV2Result
from mos3.xml_parser import parse_list_objects_v2, parse_s3_error
from std.collections import Dict


@fieldwise_init
struct S3Client(Movable, ImplicitlyCopyable, Writable):
    var credentials: S3Credentials

    @staticmethod
    def create(credentials: S3Credentials) -> Self:
        return Self(credentials=credentials)

    # ── stat (HEAD) ─────────────────────────────────────────────

    def stat(self, path: String) raises -> StatSuccess:
        """Get object metadata without downloading the body."""
        var response = _do_s3_request(self.credentials, path, "HEAD", body="")
        var status = Int(py=_get_status(response))

        if status == 200:
            return StatSuccess(
                size=Int(String(py=_get_response_header(response, "Content-Length", "0"))),
                etag=String(py=_get_response_header(response, "ETag", "")),
                last_modified=String(py=_get_response_header(response, "Last-Modified", "")),
                content_type=String(py=_get_response_header(response, "Content-Type", "")),
            )
        if status == 404:
            raise Error(String("NoSuchKey: The specified key does not exist."))
        _raise_http_error_obj(response)
        raise Error(String("Unexpected stat response"))

    # ── get (GET) ───────────────────────────────────────────────

    def get(self, path: String) raises -> GetSuccess:
        """Download an object. Returns body as String."""
        var response = _do_s3_request(self.credentials, path, "GET", body="")
        var status = Int(py=_get_status(response))

        if status == 200:
            var body_bytes = response.read()
            var body = String(py=body_bytes.decode("utf-8"))
            return GetSuccess(
                etag=String(py=_get_response_header(response, "ETag", "")),
                body=body,
            )
        if status == 404:
            raise Error(String("NoSuchKey: The specified key does not exist."))
        _raise_http_error_obj(response)
        raise Error(String("Unexpected get response"))

    # ── put (PUT) ───────────────────────────────────────────────

    def put(
        self,
        path: String,
        body: String,
        content_type: String = "application/octet-stream",
    ) raises -> PutSuccess:
        """Upload an object."""
        var content_hash = _sha256_hex(body)
        var response = _do_s3_request(
            self.credentials, path, "PUT",
            body=body,
            content_hash=content_hash,
            content_type=content_type,
        )
        var status = Int(py=_get_status(response))
        if status == 200:
            return PutSuccess(etag=String(py=_get_response_header(response, "ETag", "")))
        _raise_http_error_obj(response)
        raise Error(String("Unexpected put response"))

    # ── delete (DELETE) ─────────────────────────────────────────

    def delete(self, path: String) raises -> DeleteSuccess:
        """Delete an object. Returns DeleteSuccess even if already deleted."""
        var response = _do_s3_request(self.credentials, path, "DELETE", body="")
        var status = Int(py=_get_status(response))
        if status == 200 or status == 204:
            return DeleteSuccess()
        if status == 404:
            return DeleteSuccess()
        _raise_http_error_obj(response)
        raise Error(String("Unexpected delete response"))

    # ── list_objects ────────────────────────────────────────────

    def list_objects(
        self,
        prefix: String = "",
        max_keys: Int = 1000,
        continuation_token: String = "",
        delimiter: String = "",
    ) raises -> ListObjectsV2Result:
        """List objects in the bucket (ListObjectsV2)."""
        var search_params = "list-type=2"
        if prefix != "":
            search_params += "&prefix=" + _url_encode(prefix)
        if max_keys != 1000:
            search_params += "&max-keys=" + String(max_keys)
        if continuation_token != "":
            search_params += "&continuation-token=" + _url_encode(continuation_token)
        if delimiter != "":
            search_params += "&delimiter=" + _url_encode(delimiter)

        var response = _do_s3_request(
            self.credentials, "", "GET",
            body="",
            search_params=search_params,
        )
        var status = Int(py=_get_status(response))

        if status == 200:
            var body_bytes = response.read()
            var xml_body = String(py=body_bytes.decode("utf-8"))
            return parse_list_objects_v2(xml_body)
        if status == 404:
            raise Error(String("NoSuchBucket: The specified bucket does not exist."))
        _raise_http_error_obj(response)
        raise Error(String("Unexpected list response"))

    # ── create_bucket ───────────────────────────────────────────

    def create_bucket(self) raises -> Bool:
        """Create the configured bucket. Returns True on success."""
        var response = _do_s3_request(self.credentials, "", "PUT", body="")
        var status = Int(py=_get_status(response))
        return status == 200

    # ── copy_object ─────────────────────────────────────────────

    def copy_object(self, src: String, dst: String, dst_bucket: String = "") raises -> Bool:
        """Copy an object within or between buckets."""
        var src_bucket = self.credentials.bucket
        var copy_source = "/" + src_bucket + "/" + src

        var dest_creds = self.credentials
        if dst_bucket != "" and dst_bucket != self.credentials.bucket:
            dest_creds = S3Credentials.create(
                access_key_id=self.credentials.access_key_id,
                secret_access_key=self.credentials.secret_access_key,
                region=self.credentials.region,
                endpoint=self.credentials.endpoint,
                bucket=dst_bucket,
                session_token=self.credentials.session_token,
                virtual_hosted_style=self.credentials.virtual_hosted_style,
                insecure_http=self.credentials.insecure_http,
            )

        var empty_hash = _sha256_hex("")
        var sign_result = sign_request(dest_creds, SignOptions.create(
            path=dst,
            method="PUT",
            content_hash=empty_hash,
        ))

        var (host, port_py, path_and_query) = _parse_url(sign_result.url)
        var port = Int(py=port_py)
        var http_client = Python.import_module("http.client")
        var conn = http_client.HTTPConnection(host, port, timeout=PythonObject(30))

        var py_headers = Python.dict()
        py_headers["Authorization"] = sign_result.authorization_header
        py_headers["x-amz-content-sha256"] = sign_result.content_sha256
        py_headers["x-amz-date"] = sign_result.amz_date
        py_headers["x-amz-copy-source"] = PythonObject(copy_source)
        if sign_result.security_token_header != "":
            py_headers["x-amz-security-token"] = sign_result.security_token_header

        conn.request("PUT", path_and_query, body=PythonObject("").encode("utf-8"), headers=py_headers)
        var response = conn.getresponse()
        var status = Int(py=_get_status(response))
        if status == 200:
            return True
        _raise_http_error_obj(response)
        raise Error(String("Unexpected copy response"))

    # ── put_with_metadata ───────────────────────────────────────

    def put_with_metadata(
        self,
        path: String,
        body: String,
        metadata: Dict[String, String],
        content_type: String = "application/octet-stream",
    ) raises -> PutSuccess:
        """Upload an object with custom metadata headers."""
        var content_hash = _sha256_hex(body)
        var sign_result = sign_request(self.credentials, SignOptions.create(
            path=path,
            method="PUT",
            content_hash=content_hash,
            content_type=content_type,
        ))

        var (host, port_py, path_and_query) = _parse_url(sign_result.url)
        var port = Int(py=port_py)
        var http_client = Python.import_module("http.client")
        var conn = http_client.HTTPConnection(host, port, timeout=PythonObject(30))

        var py_headers = Python.dict()
        py_headers["Authorization"] = sign_result.authorization_header
        py_headers["x-amz-content-sha256"] = sign_result.content_sha256
        py_headers["x-amz-date"] = sign_result.amz_date
        py_headers["Content-Type"] = PythonObject(content_type)
        if sign_result.security_token_header != "":
            py_headers["x-amz-security-token"] = sign_result.security_token_header

        # Add metadata headers
        for entry in metadata.items():
            var key = "x-amz-meta-" + entry.key
            py_headers[key] = PythonObject(entry.value)

        var body_bytes = PythonObject(body).encode("utf-8")
        conn.request("PUT", path_and_query, body=body_bytes, headers=py_headers)
        var response = conn.getresponse()
        var status = Int(py=_get_status(response))

        if status == 200:
            return PutSuccess(etag=String(py=_get_response_header(response, "ETag", "")))
        _raise_http_error_obj(response)
        raise Error(String("Unexpected put_with_metadata response"))

    # ── head_object ─────────────────────────────────────────────

    def head_object(self, path: String) raises -> Dict[String, String]:
        """Return ALL response headers for an object."""
        var response = _do_s3_request(self.credentials, path, "HEAD", body="")
        var status = Int(py=_get_status(response))

        if status == 200:
            return _get_all_headers(response)
        if status == 404:
            raise Error(String("NoSuchKey: The specified key does not exist."))
        _raise_http_error_obj(response)
        raise Error(String("Unexpected head_object response"))

    # ── object_exists ───────────────────────────────────────────

    def object_exists(self, path: String) raises -> Bool:
        """Return True if the object exists."""
        var response = _do_s3_request(self.credentials, path, "HEAD", body="")
        var status = Int(py=_get_status(response))
        return status == 200

    # ── bucket_exists ───────────────────────────────────────────

    def bucket_exists(self) raises -> Bool:
        """Return True if the bucket exists (HEAD to bucket root)."""
        var response = _do_s3_request(self.credentials, "", "HEAD", body="")
        var status = Int(py=_get_status(response))
        return status == 200

    # ── get_range ───────────────────────────────────────────────

    def get_range(
        self, path: String, offset: Int, size: Int
    ) raises -> GetSuccess:
        """Download a byte range from an object."""
        var range_val = "bytes=" + String(offset) + "-" + String(offset + size - 1)

        # Build and sign the request manually to add Range header
        var sign_result = sign_request(self.credentials, SignOptions.create(
            path=path,
            method="GET",
        ))

        var (host, port_py, path_and_query) = _parse_url(sign_result.url)
        var port = Int(py=port_py)
        var http_client = Python.import_module("http.client")
        var conn = http_client.HTTPConnection(host, port, timeout=PythonObject(30))

        var py_headers = Python.dict()
        py_headers["Authorization"] = sign_result.authorization_header
        py_headers["x-amz-content-sha256"] = sign_result.content_sha256
        py_headers["x-amz-date"] = sign_result.amz_date
        py_headers["Range"] = PythonObject(range_val)
        if sign_result.security_token_header != "":
            py_headers["x-amz-security-token"] = sign_result.security_token_header

        conn.request("GET", path_and_query, body=PythonObject("").encode("utf-8"), headers=py_headers)
        var response = conn.getresponse()
        var status = Int(py=_get_status(response))

        if status == 200 or status == 206:
            var body_bytes = response.read()
            var body = String(py=body_bytes.decode("utf-8"))
            return GetSuccess(
                etag=String(py=_get_response_header(response, "ETag", "")),
                body=body,
            )
        if status == 404:
            raise Error(String("NoSuchKey: The specified key does not exist."))
        _raise_http_error_obj(response)
        raise Error(String("Unexpected get_range response"))


# ── Internal helpers ────────────────────────────────────────────


def _url_encode(s: String) raises -> String:
    """URL-encode a string using Python's urllib.parse.quote."""
    var urllib = Python.import_module("urllib.parse")
    return String(py=urllib.quote(s, safe=""))


def _get_status(response: PythonObject) raises -> PythonObject:
    """Get status code from response. Works with http.client.HTTPResponse."""
    return response.status


def _get_response_header(response: PythonObject, name: String, default: String) raises -> String:
    """Get a header from http.client.HTTPResponse."""
    try:
        var val = response.getheader(name)
        if val is None:
            return default
        return String(py=val)
    except:
        return default


def _do_s3_request(
    credentials: S3Credentials,
    path: String,
    method: String,
    body: String = "",
    content_hash: String = "",
    content_type: String = "",
    search_params: String = "",
) raises -> PythonObject:
    """
    Sign an S3 request and execute it via Python http.client.
    Returns http.client.HTTPResponse.
    """
    var hash_val = content_hash
    if hash_val == "":
        hash_val = _sha256_hex(body)

    var sign_result = sign_request(credentials, SignOptions.create(
        path=path,
        method=method,
        search_params=search_params,
        content_hash=hash_val,
        content_type=content_type,
    ))

    # Parse URL to extract host, port, path+query
    var (host, port_py, path_and_query) = _parse_url(sign_result.url)
    var port = Int(py=port_py)

    var http_client = Python.import_module("http.client")
    var conn = http_client.HTTPConnection(host, port, timeout=PythonObject(30))

    # Build headers dict
    var py_headers = Python.dict()
    py_headers["Authorization"] = sign_result.authorization_header
    py_headers["x-amz-content-sha256"] = sign_result.content_sha256
    py_headers["x-amz-date"] = sign_result.amz_date
    if sign_result.security_token_header != "":
        py_headers["x-amz-security-token"] = sign_result.security_token_header
    if content_type != "":
        py_headers["Content-Type"] = content_type

    var body_bytes = Python.none()
    if body != "":
        body_bytes = PythonObject(body).encode("utf-8")
    else:
        body_bytes = PythonObject("").encode("utf-8")

    conn.request(method, path_and_query, body=body_bytes, headers=py_headers)
    var response = conn.getresponse()
    return response


def _parse_url(url: String) raises -> Tuple[String, PythonObject, String]:
    """
    Parse a URL like 'http://host:port/path?query' into (host, port, path+query).
    Returns Tuple[String, PythonObject, String] where the port PythonObject is an int
    that Mojo can convert with Int(py=...).
    """
    var url_parse = Python.import_module("urllib.parse")
    var parsed = url_parse.urlparse(url)

    var host = String(py=parsed.hostname)
    var port = parsed.port
    if port is None:
        var scheme = String(py=parsed.scheme)
        if scheme == "https":
            port = PythonObject(443)
        else:
            port = PythonObject(80)

    var path_and_query = String(py=parsed.path)
    var query = parsed.query
    if query is not None and String(py=query) != "":
        path_and_query += "?" + String(py=query)

    return (host, port, path_and_query)


def _get_all_headers(response: PythonObject) raises -> Dict[String, String]:
    """Extract all headers from an HTTP response into a Dict."""
    var result = Dict[String, String]()
    var headers_list = response.getheaders()
    for item in headers_list:
        var key = String(py=item[0])
        var value = String(py=item[1])
        result[key] = value
    return result^


def _raise_http_error_obj(response: PythonObject) raises:
    """Try to parse an S3 error from the response body and raise it."""
    try:
        var body_bytes = response.read()
        var body = String(py=body_bytes.decode("utf-8"))
        if body != "" and "<Error>" in body:
            var (code, message) = parse_s3_error(body)
            raise Error(String(code, ": ", message))
    except e:
        _ = e
    var status = Int(py=_get_status(response))
    raise Error(String("S3 request failed with status ", status))
