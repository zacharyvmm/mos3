"""
mos3 Python extension module.
Provides S3 client functionality to Python via Mojo's PythonModuleBuilder.

Build: mojo build --emit shared-lib -I . mos3_py.mojo -o mos3_py.so
Import: import mos3_py
"""
from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder
from std.os import abort

from mos3_signing.credentials import S3Credentials
from mos3.client import S3Client


# ── Helper: extract S3Client from Python capsule ────────────────

def _unwrap_client(py_capsule: PythonObject) raises -> S3Client:
    """Extract S3Client pointer from Python capsule and return a copy."""
    var ptr = py_capsule.downcast_value_ptr[S3Client]()
    return ptr[]


# ── Exported functions ──────────────────────────────────────────


def client_new(
    access_key: PythonObject,
    secret_key: PythonObject,
    region: PythonObject,
    endpoint: PythonObject,
    bucket: PythonObject,
) raises -> PythonObject:
    """Create a new S3Client. Returns a Python capsule.
    
    client_new(access_key, secret_key, region, endpoint, bucket) -> capsule
    """
    var creds = S3Credentials.create(
        access_key_id=String(py=access_key),
        secret_access_key=String(py=secret_key),
        region=String(py=region),
        endpoint=String(py=endpoint),
        bucket=String(py=bucket),
        virtual_hosted_style=False,  # path-style for simplicity
    )
    var client = S3Client.create(creds)
    return PythonObject(alloc=client^)


def client_put(
    client_capsule: PythonObject,
    path: PythonObject,
    body: PythonObject,
    content_type: PythonObject,
) raises -> PythonObject:
    """Put an object. Returns dict with 'etag'.
    
    client_put(capsule, path, body, content_type) -> dict
    """
    var client = _unwrap_client(client_capsule)
    var result = client.put(
        String(py=path),
        String(py=body),
        String(py=content_type),
    )
    var py_result = Python.dict()
    py_result["etag"] = PythonObject(result.etag)
    return py_result


def client_get(
    client_capsule: PythonObject,
    path: PythonObject,
) raises -> PythonObject:
    """Get an object. Returns dict with 'etag' and 'body'.
    
    client_get(capsule, path) -> dict
    """
    var client = _unwrap_client(client_capsule)
    var result = client.get(String(py=path))
    var py_result = Python.dict()
    py_result["etag"] = PythonObject(result.etag)
    py_result["body"] = PythonObject(result.body)
    return py_result


def client_stat(
    client_capsule: PythonObject,
    path: PythonObject,
) raises -> PythonObject:
    """Stat an object. Returns dict with size, etag, last_modified, content_type.
    
    client_stat(capsule, path) -> dict
    """
    var client = _unwrap_client(client_capsule)
    var result = client.stat(String(py=path))
    var py_result = Python.dict()
    py_result["size"] = PythonObject(result.size)
    py_result["etag"] = PythonObject(result.etag)
    py_result["last_modified"] = PythonObject(result.last_modified)
    py_result["content_type"] = PythonObject(result.content_type)
    return py_result


def client_delete(
    client_capsule: PythonObject,
    path: PythonObject,
) raises -> PythonObject:
    """Delete an object. Returns True.
    
    client_delete(capsule, path) -> bool
    """
    var client = _unwrap_client(client_capsule)
    _ = client.delete(String(py=path))
    return PythonObject(True)


def client_list(
    client_capsule: PythonObject,
    prefix: PythonObject,
    max_keys: PythonObject,
) raises -> PythonObject:
    """List objects. Returns dict with contents array.
    
    client_list(capsule, prefix, max_keys) -> dict
    """
    var client = _unwrap_client(client_capsule)
    var result = client.list_objects(
        prefix=String(py=prefix),
        max_keys=Int(py=max_keys),
    )
    var py_result = Python.dict()
    py_result["is_truncated"] = PythonObject(result.is_truncated)
    py_result["name"] = PythonObject(result.name)
    py_result["key_count"] = PythonObject(result.key_count)

    var py_contents = Python.evaluate("[]")
    for i in range(len(result.contents)):
        var item = result.contents[i]
        var obj = Python.dict()
        obj["key"] = PythonObject(item.key)
        obj["etag"] = PythonObject(item.etag)
        obj["size"] = PythonObject(item.size)
        py_contents.append(obj)
    py_result["contents"] = py_contents
    return py_result


# ── Module init ─────────────────────────────────────────────────

@export
def PyInit_mos3_py() -> PythonObject:
    try:
        var m = PythonModuleBuilder("mos3_py")
        _ = m.add_type[S3Client]("S3Client")
        m.def_function[client_new]("client_new")
        m.def_function[client_put]("client_put")
        m.def_function[client_get]("client_get")
        m.def_function[client_stat]("client_stat")
        m.def_function[client_delete]("client_delete")
        m.def_function[client_list]("client_list")
        return m.finalize()
    except e:
        abort(String("failed to create mos3_py module: ", e))
