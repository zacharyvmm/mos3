"""
Multipart upload for S3 objects.
Implements the S3 multipart upload API: initiate, upload parts, complete, abort.
Includes concurrent part upload with ThreadPoolExecutor and retry.
"""
from std.python import Python, PythonObject
from mos3_signing.credentials import S3Credentials, SignOptions, SignResult
from mos3_signing.signing import sign_request, _sha256_hex
from mos3.client import _do_s3_request, _get_response_header, _get_status, _raise_http_error_obj


# ── Python worker for concurrent part uploads ────────────────────
# Lazily created Python function that uploads a single S3 part.
# Defined once and cached for reuse across all upload_parts calls.


def _get_upload_worker() raises -> PythonObject:
    """Get or create the Python worker function for concurrent part uploads."""
    try:
        return Python.evaluate("_upload_part")
    except:
        var __ = Python.evaluate("""
exec('''def _upload_part(url, auth_header, amz_date, content_sha256, security_token, body_bytes, part_number, retries):
    import http.client, time
    from urllib.parse import urlparse
    parsed = urlparse(url)
    host = parsed.hostname
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    path_and_query = parsed.path
    if parsed.query:
        path_and_query += "?" + parsed.query
    last_exc = Exception("unknown error")
    for attempt in range(retries + 1):
        try:
            conn = http.client.HTTPConnection(host, port, timeout=30)
            headers = {"Authorization": auth_header, "x-amz-content-sha256": content_sha256, "x-amz-date": amz_date}
            if security_token:
                headers["x-amz-security-token"] = security_token
            conn.request("PUT", path_and_query, body=body_bytes, headers=headers)
            resp = conn.getresponse()
            if resp.status == 200:
                etag = resp.getheader("ETag", "")
                conn.close()
                return (etag, part_number)
            try:
                resp.read()
            except Exception:
                pass
            conn.close()
            raise Exception("Part " + str(part_number) + " upload failed: HTTP " + str(resp.status))
        except Exception as e:
            last_exc = e
            if attempt < retries:
                time.sleep(2 ** attempt)
    raise last_exc
''')
""")
        return Python.evaluate("_upload_part")


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
        var status = _get_status(response)
        if status != 200:
            _raise_http_error_obj(response)
            raise Error(String("Failed to initiate multipart upload"))

        var body = response.text()
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
        var status = _get_status(response)
        if status != 200:
            _raise_http_error_obj(response)
            raise Error(String("Failed to upload part ", part_number))

        var etag = _get_response_header(response, "ETag", "")
        var part = PartInfo(part_number=part_number, etag=etag)
        self._parts.append(part)
        return part

    def upload_parts(mut self, parts: List[Tuple[Int, String]], queue_size: Int = 4, retry: Int = 3) raises:
        """Upload multiple parts concurrently using Python ThreadPoolExecutor.

        Each part is (part_number, data). Parts are uploaded in parallel
        with up to queue_size concurrent workers. Each part retries up
        to retry times on failure with exponential backoff.

        On success, self._parts is populated with PartInfo for all parts.
        """
        if len(parts) == 0:
            return

        var futures_mod = Python.import_module("concurrent.futures")
        var executor = futures_mod.ThreadPoolExecutor(max_workers=PythonObject(queue_size))

        var py_upload_part = _get_upload_worker()
        var py_futures = Python.list()

        # Submit all parts to the thread pool
        for i in range(len(parts)):
            var part = parts[i]
            var (part_number, data) = part

            # Pre-sign the request in Mojo (each part gets its own signature)
            var search = "partNumber=" + String(part_number) + "&uploadId=" + self.upload_id
            var content_hash = _sha256_hex(data)

            var sign_result = sign_request(self.credentials, SignOptions.create(
                path=self.key,
                method="PUT",
                search_params=search,
                content_hash=content_hash,
            ))

            var body_bytes = PythonObject(data).encode("utf-8")
            var security = sign_result.security_token_header

            var future = executor.submit(
                py_upload_part,
                PythonObject(sign_result.url),
                PythonObject(sign_result.authorization_header),
                PythonObject(sign_result.amz_date),
                PythonObject(sign_result.content_sha256),
                PythonObject(security),
                body_bytes,
                PythonObject(part_number),
                PythonObject(retry),
            )
            py_futures.append(future)

        # Collect results (waits for all to complete)
        for fut in py_futures:
            var result = fut.result()  # Python tuple: (etag, part_number)
            var etag = String(py=result[0])
            var pn = Int(py=result[1])
            var part_info = PartInfo(part_number=pn, etag=etag)
            self._parts.append(part_info)

        # Shut down the executor
        executor.shutdown(wait=PythonObject(False))

    @staticmethod
    def upload_file(
        credentials: S3Credentials,
        key: String,
        file_path: String,
        part_size: Int = 5 * 1024 * 1024,  # 5MB minimum S3 part
        queue_size: Int = 4,
        retry: Int = 3,
    ) raises -> Bool:
        """Upload a local file using concurrent multipart upload.

        Reads the file, splits it into parts, uploads them concurrently,
        and completes the multipart upload. Returns True on success.
        """
        # Read file using Python
        var py_builtins = Python.import_module("builtins")
        var f = py_builtins.open(file_path, "rb")
        var file_data = f.read()
        f.close()

        var total_size = Int(py=py_builtins.len(file_data))

        # Initiate multipart upload
        var mpu = MultipartUpload.create(credentials, key)

        if total_size == 0:
            # Empty file: just complete with no parts
            return mpu.complete()

        # Split into parts and build the parts list
        var parts_list = List[Tuple[Int, String]]()
        var part_num: Int = 1
        var offset: Int = 0

        while offset < total_size:
            var end = offset + part_size
            if end > total_size:
                end = total_size

            # Extract chunk using Python slicing
            var chunk = Python.evaluate("lambda d,o,e: d[o:e]")(file_data, PythonObject(offset), PythonObject(end))
            var chunk_str = String(py=chunk.decode("utf-8"))

            parts_list.append((part_num, chunk_str))
            part_num += 1
            offset = end

        # Upload all parts concurrently
        mpu.upload_parts(parts_list, queue_size=queue_size, retry=retry)

        # Complete the upload
        return mpu.complete()

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
        var status = _get_status(response)
        return status == 200

    def abort(self) raises -> Bool:
        """Abort the multipart upload. Returns True on success."""
        var search = "uploadId=" + self.upload_id
        var response = _do_s3_request(
            self.credentials, self.key, "DELETE",
            body="",
            search_params=search,
        )
        var status = _get_status(response)
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
