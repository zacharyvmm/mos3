"""
S3Client — the main entry point for S3 operations.
Uses Python stdlib urllib for HTTP transport (no extra deps).
"""
from std.python import Python, PythonObject
from mos3_signing.credentials import S3Credentials, SignOptions, SignResult
from mos3_signing.signing import sign_request, _sha256_hex
from mos3_signing.error import S3Error
from mos3.types import StatSuccess, GetSuccess, PutSuccess, DeleteSuccess, ListObjectsV2Result
from mos3.xml_parser import parse_list_objects_v2, parse_s3_error


@fieldwise_init
struct S3Client(Movable):
    var credentials: S3Credentials

    @staticmethod
    def create(credentials: S3Credentials) -> Self:
        return Self(credentials=credentials)

    # ── stat (HEAD) ─────────────────────────────────────────────

    def stat(self, path: String) raises -> StatSuccess:
        """Get object metadata without downloading the body."""
        var response = _do_s3_request(self.credentials, path, "HEAD", body="")
        var status = Int(py=response.status_code)

        if status == 200:
            var headers = response.headers
            return StatSuccess(
                size=Int(String(py=headers.get("Content-Length", "0"))),
                etag=String(py=headers.get("ETag", "")),
                last_modified=String(py=headers.get("Last-Modified", "")),
                content_type=String(py=headers.get("Content-Type", "")),
            )
        if status == 404:
            raise Error(String("NoSuchKey: The specified key does not exist."))
        _raise_http_error(response)
        raise Error(String("Unexpected stat response"))

    # ── get (GET) ───────────────────────────────────────────────

    def get(self, path: String) raises -> GetSuccess:
        """Download an object. Returns body as String."""
        var response = _do_s3_request(self.credentials, path, "GET", body="")
        var status = Int(py=response.status_code)

        if status == 200:
            var headers = response.headers
            var body_bytes = response.read()
            var body = String(py=body_bytes.decode("utf-8"))
            return GetSuccess(
                etag=String(py=headers.get("ETag", "")),
                body=body,
            )
        if status == 404:
            raise Error(String("NoSuchKey: The specified key does not exist."))
        _raise_http_error(response)
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
        var status = Int(py=response.status_code)
        if status == 200:
            var headers = response.headers
            return PutSuccess(etag=String(py=headers.get("ETag", "")))
        _raise_http_error(response)
        raise Error(String("Unexpected put response"))

    # ── delete (DELETE) ─────────────────────────────────────────

    def delete(self, path: String) raises -> DeleteSuccess:
        """Delete an object. Returns DeleteSuccess even if already deleted."""
        var response = _do_s3_request(self.credentials, path, "DELETE", body="")
        var status = Int(py=response.status_code)
        if status == 200 or status == 204:
            return DeleteSuccess()
        if status == 404:
            # Already deleted — still success from caller's perspective
            return DeleteSuccess()
        _raise_http_error(response)
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
        var status = Int(py=response.status_code)

        if status == 200:
            var body_bytes = response.read()
            var xml_body = String(py=body_bytes.decode("utf-8"))
            return parse_list_objects_v2(xml_body)
        if status == 404:
            raise Error(String("NoSuchBucket: The specified bucket does not exist."))
        _raise_http_error(response)
        raise Error(String("Unexpected list response"))


# ── Internal helpers ────────────────────────────────────────────


def _url_encode(s: String) raises -> String:
    """URL-encode a string using Python's urllib.parse.quote."""
    var urllib = Python.import_module("urllib.parse")
    return String(py=urllib.quote(s, safe=""))


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
    Sign an S3 request and execute it via Python urllib.
    Returns the HTTP response as a PythonObject.
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

    var urllib_request = Python.import_module("urllib.request")
    var req = urllib_request.Request(sign_result.url, method=method)
    req.add_header("Authorization", sign_result.authorization_header)
    req.add_header("x-amz-content-sha256", sign_result.content_sha256)
    req.add_header("x-amz-date", sign_result.amz_date)
    if sign_result.security_token_header != "":
        req.add_header("x-amz-security-token", sign_result.security_token_header)
    if content_type != "":
        req.add_header("Content-Type", content_type)

    var data = Python.none()
    if body != "":
        data = PythonObject(body.encode("utf-8"))

    var response = urllib_request.urlopen(req, data=data)
    return response


def _raise_http_error(response: PythonObject) raises:
    """Try to parse an S3 error from the response body and raise it."""
    try:
        var body_bytes = response.read()
        var body = String(py=body_bytes.decode("utf-8"))
        if body != "" and "<Error>" in body:
            var (code, message) = parse_s3_error(body)
            raise Error(String(code, ": ", message))
    except e:
        _ = e  # Fall through
    var status = Int(py=response.status_code)
    raise Error(String("S3 request failed with status ", status))
