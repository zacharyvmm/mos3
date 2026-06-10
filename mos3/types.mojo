"""
Result types for S3 operations.
Mirrors the result structs in Bun's simple_request.rs.
"""
from mos3_signing.error import S3Error


@fieldwise_init
struct StatSuccess(Movable, Copyable, ImplicitlyCopyable):
    """Result of a successful stat (HEAD) request."""
    var size: Int
    var etag: String
    var last_modified: String
    var content_type: String


@fieldwise_init
struct GetSuccess(Movable, Copyable, ImplicitlyCopyable):
    """Result of a successful get (GET) request."""
    var etag: String
    var body: String


@fieldwise_init
struct PutSuccess(Movable, Copyable, ImplicitlyCopyable):
    """Result of a successful put (PUT) request."""
    var etag: String     # ETag of the uploaded object


@fieldwise_init
struct UploadProgress(Movable, Copyable, ImplicitlyCopyable):
    """Progress information for auto-multipart uploads."""
    var bytes_uploaded: Int
    var total_bytes: Int
    var parts_completed: Int
    var total_parts: Int


struct DeleteSuccess(Movable, Copyable):
    """Result of a successful delete request."""
    var _dummy: Bool

    def __init__(out self):
        self._dummy = False


@fieldwise_init
struct ListObjectsContents(Movable, Copyable, ImplicitlyCopyable):
    """A single object in a list-objects response."""
    var key: String
    var etag: String
    var size: Int
    var last_modified: String
    var storage_class: String


@fieldwise_init
struct ListObjectsV2Result(Movable, Copyable):
    """Result of a list-objects-v2 request."""
    var is_truncated: Bool
    var contents: List[ListObjectsContents]
    var name: String
    var prefix: String
    var max_keys: Int
    var key_count: Int
    var continuation_token: String
    var next_continuation_token: String
    var common_prefixes: List[String]
    var delimiter: String
