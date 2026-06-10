# mos3

[![Mojo](https://img.shields.io/badge/Mojo-0.26%2B-%23FF4C00?logo=mojo)](https://www.modular.com/mojo)

**The missing S3 client for Mojo — performant, ergonomic, AWS Signature V4.**

`mos3` is a pure-Mojo S3 client library with AWS Signature V4 signing, no external dependencies beyond the Python standard library (used only for HTTP transport). Inspired by [Bun's S3 client](https://github.com/oven-sh/bun), it provides a clean, typed API with streaming support, multipart uploads, presigned URLs, and automatic multipart for large objects.

---

## Quickstart

```mojo
from mos3_signing.credentials import S3Credentials
from mos3.client import S3Client

def main() raises:
    var creds = S3Credentials.create(
        access_key_id="YOUR_ACCESS_KEY",
        secret_access_key="YOUR_SECRET_KEY",
        region="us-east-1",
        endpoint="s3.amazonaws.com",
        bucket="my-bucket",
    )
    var client = S3Client.create(creds)

    # Put
    var put_result = client.put("hello.txt", "Hello from Mojo!")
    print("ETag:", put_result.etag)

    # Get
    var get_result = client.get("hello.txt")
    print(get_result.body)

    # Stat
    var stat_result = client.stat("hello.txt")
    print("Size:", stat_result.size, "bytes")

    # List
    var list_result = client.list_objects(prefix="photos/")
    for item in list_result.contents:
        print(" ", item.key, item.size, "bytes")

    # Delete
    _ = client.delete("hello.txt")
```

You can also load credentials from environment variables:

```mojo
var creds = S3Credentials.from_env(bucket="my-bucket")
```

Requires `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optionally `AWS_REGION`, `AWS_ENDPOINT_URL`, and `AWS_SESSION_TOKEN`.

---

## Install

Add Mojo + `mos3` to your project:

```bash
# Create a virtual environment and install Mojo
python3 -m venv .venv
.venv/bin/pip install mojo

# Clone mos3
git clone https://github.com/zacharyvmm/mos3.git
cd mos3

# Link into your Mojo project's include path:
# mos3 uses `from mos3.client import S3Client` style imports,
# so ensure the repo root is on MOJO_PATH or use -I .
```

---

## Features

| Feature | Method / Function |
|---|---|
| **Object stat (HEAD)** | `client.stat(path) -> StatSuccess` |
| **Object get** | `client.get(path) -> GetSuccess` |
| **Object put** | `client.put(path, body) -> PutSuccess` |
| **Object delete** | `client.delete(path) -> DeleteSuccess` |
| **List objects (v2)** | `client.list_objects(prefix=..., max_keys=...) -> ListObjectsV2Result` |
| **Byte-range get** | `client.get_range(path, offset, size) -> GetSuccess` |
| **Copy object** | `client.copy_object(src, dst, dst_bucket=...) -> Bool` |
| **Create bucket** | `client.create_bucket() -> Bool` |
| **Bucket exists** | `client.bucket_exists() -> Bool` |
| **Object exists** | `client.object_exists(path) -> Bool` |
| **Head all headers** | `client.head_object(path) -> Dict[String, String]` |
| **Put with metadata** | `client.put_with_metadata(path, body, metadata) -> PutSuccess` |
| **Put file from disk** | `client.put_file(path, file_path) -> PutSuccess` |
| **Auto-multipart put** | `client.put_auto(path, body, part_size=...) -> PutSuccess` |
| **Put with progress** | `client.put_with_progress(path, body, on_progress) -> PutSuccess` |
| **Multipart upload** | `MultipartUpload.create(creds, key)` + `upload_part()` + `complete()` / `abort()` |
| **Concurrent multipart** | `MultipartUpload.upload_parts(parts, queue_size=..., retry=...)` (ThreadPoolExecutor) |
| **Multipart file** | `MultipartUpload.upload_file(creds, key, file_path)` |
| **Streaming download** | `DownloadStream.create(creds, path, chunk_size=...)` |
| **Presigned GET URL** | `presigned_get(credentials, path, expires_in=...) -> String` |
| **Presigned PUT URL** | `presigned_put(credentials, path, expires_in=..., content_type=...) -> String` |
| **Automatic retry** | Exponential backoff on 5xx / connection errors (configurable via `RetryConfig`) |
| **AWS Signature V4** | Pure Mojo canonical request builder, HMAC via Python (once per sign). Supports session tokens. |

---

## Examples

See the [`examples/`](examples/) directory for runnable examples:

- [`basic_usage.mojo`](examples/basic_usage.mojo) — put, get, stat, delete, list
- [`presigned_url.mojo`](examples/presigned_url.mojo) — generate and use presigned URLs
- [`multipart_upload.mojo`](examples/multipart_upload.mojo) — upload a large object via multipart
- [`streaming_download.mojo`](examples/streaming_download.mojo) — download in chunks

All examples work against a local [moto](https://github.com/getmoto/moto) S3 mock server.

---

## Testing

Integration tests run against a [moto](https://github.com/getmoto/moto) S3 mock server:

```bash
# Install moto in the virtual environment
.venv/bin/pip install moto

# Run all integration tests
python3 tests/test_integration_moto.py
```

Unit tests (signing, crypto, XML parsing, etc.):

```bash
.venv/bin/mojo run -I . tests/test_signing.mojo
.venv/bin/mojo run -I . tests/test_crypto.mojo
.venv/bin/mojo run -I . tests/test_xml_parsing.mojo
.venv/bin/mojo run -I . tests/test_credentials.mojo
```

---

## Architecture

`mos3` is organized in layers:

```
mos3_signing/       Layer 1: AWS Signature V4 + credential types (pure Mojo)
  ├── signing.mojo         sign_request(), presigned_get(), presigned_put()
  ├── credentials.mojo     S3Credentials, SignOptions, SignResult
  ├── crypto.mojo          HMAC-SHA256 via Python hashlib
  ├── crypto_sha256.mojo   Pure-Mojo SHA256 implementation
  ├── utils.mojo           hex_encode, uri_encode
  └── error.mojo           S3Error, error messages

mos3/               Layer 2: S3 HTTP client
  ├── client.mojo          S3Client with all operations + retry logic
  ├── types.mojo           StatSuccess, GetSuccess, PutSuccess, etc.
  ├── stream/
  │   ├── upload.mojo      MultipartUpload (sequential + concurrent)
  │   └── download.mojo    DownloadStream (chunked reading)
  └── xml_parser.mojo      S3 XML response parsing

mos3_py.mojo        Python extension module (optional)
```

---

## Inspiration

- [Bun S3 Client](https://github.com/oven-sh/bun) — the Mojo API mirrors Bun's `S3Client`, `S3Credentials`, and result structs
- AWS Signature V4 [documentation](https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html)

## License

MIT
