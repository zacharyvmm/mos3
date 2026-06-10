"""
Streaming download for S3 objects.
Reads response body in configurable chunk sizes via Python urllib.
"""
from std.python import Python, PythonObject
from mos3_signing.credentials import S3Credentials, SignOptions
from mos3_signing.signing import sign_request, _sha256_hex
from mos3.xml_parser import parse_s3_error


@fieldwise_init
struct DownloadStream(Movable):
    """A streaming S3 download. Call read_chunk() to get the next chunk."""
    var _response: PythonObject
    var _etag: String
    var _chunk_size: Int

    @staticmethod
    def create(
        credentials: S3Credentials,
        path: String,
        chunk_size: Int = 8192,
    ) raises -> Self:
        """Start a streaming download of an S3 object."""
        var sign_result = sign_request(credentials, SignOptions.create(
            path=path,
            method="GET",
        ))

        var urllib_request = Python.import_module("urllib.request")
        var req = urllib_request.Request(sign_result.url, method="GET")
        req.add_header("Authorization", sign_result.authorization_header)
        req.add_header("x-amz-content-sha256", sign_result.content_sha256)
        req.add_header("x-amz-date", sign_result.amz_date)
        if sign_result.security_token_header != "":
            req.add_header("x-amz-security-token", sign_result.security_token_header)

        var response = urllib_request.urlopen(req)
        var status = Int(py=response.getcode())
        if status != 200:
            var body_bytes = response.read()
            var body = String(py=body_bytes.decode("utf-8"))
            if "<Error>" in body:
                var (code, message) = parse_s3_error(body)
                raise Error(String(code, ": ", message))
            raise Error(String("Download failed with status ", status))

        var etag = ""
        try:
            var h = response.getheader("ETag")
            if h is not None:
                etag = String(py=h)
        except:
            pass

        return Self(
            _response=response,
            _etag=etag,
            _chunk_size=chunk_size,
        )

    def etag(self) -> String:
        """Get the ETag of the downloaded object (available after create)."""
        return self._etag

    def read_chunk(self) raises -> String:
        """Read the next chunk from the stream. Returns empty string when done."""
        var chunk_bytes = self._response.read(self._chunk_size)
        if chunk_bytes is None:
            return ""
        var chunk_str = String(py=chunk_bytes.decode("utf-8"))
        if chunk_str == "":
            return ""
        return chunk_str

    def read_all(self) raises -> String:
        """Read the entire remaining body. Convenience method."""
        var result = String("")
        while True:
            var chunk = self.read_chunk()
            if chunk == "":
                break
            result += chunk
        return result

    def close(self):
        """Close the underlying HTTP connection."""
        try:
            self._response.close()
        except:
            pass
