"""
AWS Signature V4 implementation.
Uses Python hashlib for SHA256/HMAC-SHA256 (Mojo has no native crypto).
The canonical request logic is pure Mojo.
"""
from std.python import Python, PythonObject
from mos3_signing.credentials import S3Credentials, SignOptions, SignResult
from mos3_signing.utils import hex_encode, uri_encode
from mos3_signing.error import S3Error


# ── Crypto helpers (Python-backed) ──────────────────────────────


def _sha256_hex(data: String) raises -> String:
    """Compute SHA256 hash of data, return lowercase hex string."""
    var hashlib = Python.import_module("hashlib")
    var py_data = PythonObject(data)
    var h = hashlib.sha256(py_data.encode("utf-8"))
    return String(py=h.hexdigest())


def _hmac_sha256(key_hex: String, data: String) raises -> String:
    """
    Compute HMAC-SHA256(key_hex, data).
    key_hex is the hex-encoded key (from previous HMAC step).
    Returns lowercase hex string.
    """
    var hashlib = Python.import_module("hashlib")
    var hmac = Python.import_module("hmac")
    # Decode hex key to raw bytes
    var raw_key = Python.evaluate("bytes.fromhex")(key_hex)
    var py_data = PythonObject(data)
    var h = hmac.new(raw_key, py_data.encode("utf-8"), hashlib.sha256)
    return String(py=h.hexdigest())


# ── AWS Signature V4 core ───────────────────────────────────────


def sign_request(credentials: S3Credentials, options: SignOptions) raises -> SignResult:
    """
    Sign an S3 request with AWS Signature V4.

    Returns a SignResult with the authorization header, full URL, and
    required headers for the HTTP request.
    """
    # Validate credentials
    if credentials.access_key_id == "" or credentials.secret_access_key == "":
        raise Error(String("Missing required S3 credentials"))

    # Validate method
    var method_upper = options.method
    if method_upper not in ("GET", "PUT", "HEAD", "DELETE", "POST"):
        raise Error(String("Invalid HTTP method: ", options.method))

    # Get current UTC time
    var datetime = Python.import_module("datetime")
    var now = datetime.datetime.now(datetime.timezone.utc)
    var amz_date = String(py=now.strftime("%Y%m%dT%H%M%SZ"))
    var date_stamp = String(py=now.strftime("%Y%m%d"))

    # Content hash — use provided or compute empty-string hash
    var content_hash = options.content_hash
    if content_hash == "":
        content_hash = _sha256_hex("")

    # Build host
    var host = credentials.endpoint
    if credentials.virtual_hosted_style and credentials.bucket != "":
        host = credentials.bucket + "." + credentials.endpoint

    # Build full path: for path-style addressing, prepend bucket
    var raw_path = options.path
    if not raw_path.startswith("/"):
        raw_path = "/" + raw_path

    # Prepend bucket for path-style addressing
    if not credentials.virtual_hosted_style and credentials.bucket != "":
        raw_path = "/" + credentials.bucket + raw_path

    # Canonical URI — path-encode the full path, preserving '/'
    var canonical_uri = uri_encode(raw_path, encode_slash=False)
    if not canonical_uri.startswith("/"):
        canonical_uri = "/" + canonical_uri

    # Build URL path (same as canonical URI for S3)
    var url_path = canonical_uri

    # Canonical query string (already built by caller)
    var canonical_query = options.search_params

    # Signed headers (alphabetical: host, x-amz-content-sha256, x-amz-date, [+ x-amz-security-token])
    var signed_headers = "host;x-amz-content-sha256;x-amz-date"
    if credentials.session_token != "":
        signed_headers += ";x-amz-security-token"

    # Canonical headers
    var canonical_headers = "host:" + host + "\n"
    canonical_headers += "x-amz-content-sha256:" + content_hash + "\n"
    canonical_headers += "x-amz-date:" + amz_date + "\n"
    if credentials.session_token != "":
        canonical_headers += "x-amz-security-token:" + credentials.session_token + "\n"

    # Build canonical request
    var canonical_request = method_upper + "\n"
    canonical_request += canonical_uri + "\n"
    canonical_request += canonical_query + "\n"
    canonical_request += canonical_headers + "\n"
    canonical_request += signed_headers + "\n"
    canonical_request += content_hash

    # Build string-to-sign
    var credential_scope = date_stamp + "/" + credentials.region + "/s3/aws4_request"
    var string_to_sign = "AWS4-HMAC-SHA256\n"
    string_to_sign += amz_date + "\n"
    string_to_sign += credential_scope + "\n"
    string_to_sign += _sha256_hex(canonical_request)

    # Compute signing key via HMAC chain
    # Step 1: key = raw bytes of "AWS4<secret>", data = date_stamp
    # We hex-encode the key so _hmac_sha256 can decode it back to raw bytes
    var k_date = _hmac_sha256(hex_encode("AWS4" + credentials.secret_access_key), date_stamp)
    var k_region = _hmac_sha256(k_date, credentials.region)
    var k_service = _hmac_sha256(k_region, "s3")
    var k_signing = _hmac_sha256(k_service, "aws4_request")
    var signature = _hmac_sha256(k_signing, string_to_sign)

    # Build authorization header
    var authorization = "AWS4-HMAC-SHA256 "
    authorization += "Credential=" + credentials.access_key_id
    authorization += "/" + credential_scope + ", "
    authorization += "SignedHeaders=" + signed_headers + ", "
    authorization += "Signature=" + signature

    # Build URL
    var scheme = "http" if credentials.insecure_http else "https"
    var url = scheme + "://" + host + url_path
    if options.search_params != "":
        url += "?" + options.search_params

    return SignResult(
        url=url,
        authorization_header=authorization,
        amz_date=amz_date,
        content_sha256=content_hash,
        security_token_header=credentials.session_token,
    )
