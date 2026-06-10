"""
AWS Signature V4 implementation.
SHA256 is pure Mojo. HMAC-SHA256 uses Python (called only once per sign).
The canonical request logic is pure Mojo.
"""
from std.python import Python, PythonObject
from std.collections import Dict
from mos3_signing.credentials import S3Credentials, SignOptions, SignResult
from mos3_signing.utils import hex_encode, uri_encode
from mos3_signing.error import S3Error
from mos3_signing.crypto_sha256 import sha256 as _sha256_hex
from mos3_signing.crypto import hmac_sha256_hex_key as _hmac_sha256


# ── AWS Signature V4 core ───────────────────────────────────────


def _derive_signing_key(secret_access_key: String, date_stamp: String, region: String) raises -> String:
    """Derive the AWS V4 signing key via the HMAC chain.
    
    Steps: kDate→kRegion→kService→kSigning.
    Returns the final hex-encoded signing key.
    """
    var k_date = _hmac_sha256(hex_encode("AWS4" + secret_access_key), date_stamp)
    var k_region = _hmac_sha256(k_date, region)
    var k_service = _hmac_sha256(k_region, "s3")
    var k_signing = _hmac_sha256(k_service, "aws4_request")
    return k_signing


# ── Presigned URL generation ────────────────────────────────────


def presigned_get(credentials: S3Credentials, path: String, expires_in: Int = 3600) raises -> String:
    """Generate a presigned GET URL for temporary S3 object access."""
    return _presigned_url(credentials, path, "GET", expires_in, "")


def presigned_put(credentials: S3Credentials, path: String, expires_in: Int = 3600, content_type: String = "") raises -> String:
    """Generate a presigned PUT URL for uploading to S3."""
    return _presigned_url(credentials, path, "PUT", expires_in, content_type)


@fieldwise_init
struct PresignedPost(Movable, Copyable):
    """A presigned POST form for browser-based uploads to S3."""
    var url: String
    var fields: Dict[String, String]


def _json_escape(s: String) -> String:
    """Escape a string for safe inclusion in a JSON string value.

    Handles backslash, double-quote, and common control characters.
    """
    var result = s
    # Order matters: escape backslash first so we don't re-escape
    # the backslashes we just inserted
    result = result.replace("\\", "\\\\")
    result = result.replace('"', '\\"')
    result = result.replace("\n", "\\n")
    result = result.replace("\r", "\\r")
    result = result.replace("\t", "\\t")
    return result


def presigned_post(
    credentials: S3Credentials,
    key: String,
    expires_in: Int = 3600,
    max_content_length: Int = 10485760,  # 10 MB
    acl: String = "private",
) raises -> PresignedPost:
    """Generate a presigned POST form for browser uploads to S3.

    Returns a PresignedPost with url and fields dict.
    The fields can be used in an HTML form to upload files directly.
    """
    # Validate credentials
    if credentials.access_key_id == "" or credentials.secret_access_key == "":
        raise Error(String("Missing required S3 credentials"))

    # Get current UTC time
    var datetime = Python.import_module("datetime")
    var now = datetime.datetime.now(datetime.timezone.utc)
    var expiration = now + datetime.timedelta(seconds=PythonObject(expires_in))
    var exp_str = String(py=expiration.strftime("%Y-%m-%dT%H:%M:%SZ"))
    var amz_date = String(py=now.strftime("%Y%m%dT%H%M%SZ"))
    var date_stamp = String(py=now.strftime("%Y%m%d"))

    var credential_scope = date_stamp + "/" + credentials.region + "/s3/aws4_request"
    var credential = credentials.access_key_id + "/" + credential_scope

    # Build URL
    var scheme = "http" if credentials.insecure_http else "https"
    var host = credentials.endpoint
    if not credentials.virtual_hosted_style and credentials.bucket != "":
        host = host + "/" + credentials.bucket
    var url = scheme + "://" + host + "/"

    # Build fields dict
    var fields = Dict[String, String]()
    fields["key"] = key
    fields["acl"] = acl
    fields["X-Amz-Algorithm"] = "AWS4-HMAC-SHA256"
    fields["X-Amz-Credential"] = credential
    fields["X-Amz-Date"] = amz_date

    if credentials.session_token != "":
        fields["X-Amz-Security-Token"] = credentials.session_token

    # Build policy JSON document as a String (no Python JSON dependency)
    # Shape: {"expiration":"...","conditions":[{"bucket":"..."},{"key":"..."},{"acl":"..."},["content-length-range",1,N]]}
    var policy_json = '{"expiration":"' + exp_str + '","conditions":['
    policy_json += '{"bucket":"' + _json_escape(credentials.bucket) + '"},'
    policy_json += '{"key":"' + _json_escape(key) + '"},'
    policy_json += '{"acl":"' + acl + '"},'
    var max_len_str = String(py=PythonObject(max_content_length).__str__())
    policy_json += '["content-length-range",1,' + max_len_str + ']'
    policy_json += ']}'

    # Base64 encode the policy
    var base64 = Python.import_module("base64")
    var policy_b64 = String(py=base64.b64encode(PythonObject(policy_json).encode("utf-8")).decode("utf-8"))

    # Sign the base64-encoded policy
    var signing_key = _derive_signing_key(credentials.secret_access_key, date_stamp, credentials.region)
    var signature = _hmac_sha256(signing_key, policy_b64)

    fields["policy"] = policy_b64
    fields["X-Amz-Signature"] = signature

    return PresignedPost(url=url, fields=fields^)


def _presigned_url(
    credentials: S3Credentials,
    path: String,
    method: String,
    expires_in: Int,
    content_type: String,
) raises -> String:
    """Core presigned URL builder for GET and PUT."""
    # Validate credentials
    if credentials.access_key_id == "" or credentials.secret_access_key == "":
        raise Error(String("Missing required S3 credentials"))

    # Get current UTC time
    var datetime = Python.import_module("datetime")
    var now = datetime.datetime.now(datetime.timezone.utc)
    var amz_date = String(py=now.strftime("%Y%m%dT%H%M%SZ"))
    var date_stamp = String(py=now.strftime("%Y%m%d"))

    # Build host
    var host = credentials.endpoint
    if credentials.virtual_hosted_style and credentials.bucket != "":
        host = credentials.bucket + "." + credentials.endpoint

    # Build full path
    var raw_path = path
    if not raw_path.startswith("/"):
        raw_path = "/" + raw_path
    if not credentials.virtual_hosted_style and credentials.bucket != "":
        raw_path = "/" + credentials.bucket + raw_path

    # Canonical URI
    var canonical_uri = uri_encode(raw_path, encode_slash=False)
    if not canonical_uri.startswith("/"):
        canonical_uri = "/" + canonical_uri

    # Signed headers (alphabetical: content-type before host)
    var signed_headers: String
    if content_type != "":
        signed_headers = "content-type;host"
    else:
        signed_headers = "host"

    # Build query params for the canonical request
    var credential_scope = date_stamp + "/" + credentials.region + "/s3/aws4_request"
    var credential_value = credentials.access_key_id + "/" + credential_scope

    # Convert expires_in to string (use Python for Int→String)
    var expires_str = String(py=PythonObject(expires_in).__str__())

    # Canonical query string — params in alphabetical order, values URI-encoded
    var canonical_query = "X-Amz-Algorithm=AWS4-HMAC-SHA256"
    canonical_query += "&X-Amz-Credential=" + uri_encode(credential_value, encode_slash=True)
    canonical_query += "&X-Amz-Date=" + amz_date
    canonical_query += "&X-Amz-Expires=" + expires_str
    if credentials.session_token != "":
        canonical_query += "&X-Amz-Security-Token=" + uri_encode(credentials.session_token, encode_slash=True)
    canonical_query += "&X-Amz-SignedHeaders=" + uri_encode(signed_headers, encode_slash=True)

    # Content hash is always UNSIGNED-PAYLOAD for presigned URLs
    var content_hash = "UNSIGNED-PAYLOAD"

    # Canonical headers (alphabetical order)
    var canonical_headers: String
    if content_type != "":
        canonical_headers = "content-type:" + content_type + "\nhost:" + host + "\n"
    else:
        canonical_headers = "host:" + host + "\n"

    # Build canonical request
    var canonical_request = method + "\n"
    canonical_request += canonical_uri + "\n"
    canonical_request += canonical_query + "\n"
    canonical_request += canonical_headers + "\n"
    canonical_request += signed_headers + "\n"
    canonical_request += content_hash

    # Build string-to-sign (same as normal V4)
    var string_to_sign = "AWS4-HMAC-SHA256\n"
    string_to_sign += amz_date + "\n"
    string_to_sign += credential_scope + "\n"
    string_to_sign += _sha256_hex(canonical_request)

    # Compute signing key via HMAC chain
    var signing_key = _derive_signing_key(credentials.secret_access_key, date_stamp, credentials.region)
    var signature = _hmac_sha256(signing_key, string_to_sign)

    # Build final URL query string (canonical + signature appended)
    var query_string = canonical_query + "&X-Amz-Signature=" + signature

    # Build final URL
    var scheme = "http" if credentials.insecure_http else "https"
    var url = scheme + "://" + host + canonical_uri + "?" + query_string
    return url


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
    # We hex-encode the key so _hmac_sha256 can decode it back to raw bytes
    var signing_key = _derive_signing_key(credentials.secret_access_key, date_stamp, credentials.region)
    var signature = _hmac_sha256(signing_key, string_to_sign)

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
