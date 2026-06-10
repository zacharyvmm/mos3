"""
mos3_py — Python extension module for mos3 S3 client library.

Usage from Python:
    import mos3_py
    client = mos3_py.client_new("AKIA...", "secret...", "us-east-1", "127.0.0.1:15001", "test-bucket")
    result = mos3_py.client_get(client, "test.txt")
"""
from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder
from std.os import abort
from std.memory import UnsafePointer

from mos3_signing.credentials import S3Credentials
from mos3.client import S3Client


# ═══════════════════════════════════════════════════════════════
# Capsule helpers — wrap/unwrap S3Client* via pointer-as-int
# ═══════════════════════════════════════════════════════════════

alias ClientPtr = UnsafePointer[S3Client]


fn _alloc_client(client: S3Client) raises -> ClientPtr:
    """Allocate an S3Client on the heap, store it, return pointer."""
    var ptr = ClientPtr.alloc(1)
    # Move client into the allocated memory
    var move_dst = ptr.bitcast[NoneType]()  # Not needed, just store directly
    _ = move_dst
    ptr.store(client^)
    return ptr


fn _free_client(ptr: ClientPtr) raises:
    """Destroy and free a heap-allocated S3Client."""
    ptr[].destroy()  # or just ptr.free()
    ptr.free()


fn _client_ptr_to_py(ptr: ClientPtr) raises -> PythonObject:
    """Convert a pointer to a Python int (the address)."""
    var addr = ptr.__as_index()
    return PythonObject(Int(addr))


fn _py_to_client_ptr(py_obj: PythonObject) raises -> ClientPtr:
    """Convert a Python int back to a pointer."""
    var addr = Int(py_obj)
    return ClientPtr.from_address(addr)


# ═══════════════════════════════════════════════════════════════
# Module functions (exported to Python)
# ═══════════════════════════════════════════════════════════════


@export
def PyInit_mos3_py() -> PythonObject:
    try:
        var m = PythonModuleBuilder("mos3_py")
        m.def_function[client_new]("client_new")
        m.def_function[client_get]("client_get")
        m.def_function[client_put]("client_put")
        m.def_function[client_delete]("client_delete")
        m.def_function[client_list]("client_list")
        m.def_function[client_stat]("client_stat")
        return m.finalize()
    except e:
        abort(String("failed to create module: ", e))


# ── client_new(access_key, secret_key, region, endpoint, bucket) ──
def client_new(
    access_key: String,
    secret_key: String,
    region: String,
    endpoint: String,
    bucket: String,
) raises -> PythonObject:
    var creds = S3Credentials.create(
        access_key_id=access_key,
        secret_access_key=secret_key,
        region=region,
        endpoint=endpoint,
        bucket=bucket,
        virtual_hosted_style=False,
        insecure_http=True,
    )
    var client = S3Client.create(creds)
    var ptr = _alloc_client(client^)
    return _client_ptr_to_py(ptr)


# ── client_get(client_int, path) ──
def client_get(client_obj: PythonObject, path: String) raises -> PythonObject:
    var ptr = _py_to_client_ptr(client_obj)
    var result = ptr[].get(path)
    var py_result = Python.dict()
    py_result["etag"] = PythonObject(result.etag)
    py_result["body"] = PythonObject(result.body)
    return py_result


# ── client_put(client_int, path, body, content_type) ──
def client_put(
    client_obj: PythonObject,
    path: String,
    body: String,
    content_type: String = "application/octet-stream",
) raises -> PythonObject:
    var ptr = _py_to_client_ptr(client_obj)
    var result = ptr[].put(path, body, content_type)
    var py_result = Python.dict()
    py_result["etag"] = PythonObject(result.etag)
    return py_result


# ── client_delete(client_int, path) ──
def client_delete(client_obj: PythonObject, path: String) raises -> PythonObject:
    var ptr = _py_to_client_ptr(client_obj)
    var __result = ptr[].delete(path)
    return PythonObject(True)


# ── client_list(client_int, prefix, max_keys) ──
def client_list(
    client_obj: PythonObject,
    prefix: String = "",
    max_keys: Int = 1000,
) raises -> PythonObject:
    var ptr = _py_to_client_ptr(client_obj)
    var result = ptr[].list_objects(prefix=prefix, max_keys=max_keys)
    var py_result = Python.dict()
    py_result["is_truncated"] = PythonObject(result.is_truncated)
    py_result["key_count"] = PythonObject(result.key_count)
    py_result["max_keys"] = PythonObject(result.max_keys)
    py_result["name"] = PythonObject(result.name)
    py_result["prefix"] = PythonObject(result.prefix)
    py_result["continuation_token"] = PythonObject(result.continuation_token)
    py_result["next_continuation_token"] = PythonObject(result.next_continuation_token)
    py_result["delimiter"] = PythonObject(result.delimiter)

    var py_contents = Python.list()
    for i in range(len(result.contents)):
        var item = result.contents[i]
        var py_item = Python.dict()
        py_item["key"] = PythonObject(item.key)
        py_item["etag"] = PythonObject(item.etag)
        py_item["size"] = PythonObject(item.size)
        py_item["last_modified"] = PythonObject(item.last_modified)
        py_item["storage_class"] = PythonObject(item.storage_class)
        py_contents.append(py_item)
    py_result["contents"] = py_contents

    var py_prefixes = Python.list()
    for i in range(len(result.common_prefixes)):
        py_prefixes.append(PythonObject(result.common_prefixes[i]))
    py_result["common_prefixes"] = py_prefixes

    return py_result


# ── client_stat(client_int, path) ──
def client_stat(client_obj: PythonObject, path: String) raises -> PythonObject:
    var ptr = _py_to_client_ptr(client_obj)
    var result = ptr[].stat(path)
    var py_result = Python.dict()
    py_result["size"] = PythonObject(result.size)
    py_result["etag"] = PythonObject(result.etag)
    py_result["last_modified"] = PythonObject(result.last_modified)
    py_result["content_type"] = PythonObject(result.content_type)
    return py_result
