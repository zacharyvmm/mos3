#!/usr/bin/env python3
"""
Benchmark suite comparing mos3 vs boto3 against a moto S3 mock server.

Usage:
    python3 tests/benchmark.py           # run from project root
    python3 tests/benchmark.py --quick   # fewer iterations for faster results
"""

import time
import sys
import os
import subprocess
import io
import random
import string

# Add project root to path so we can import mos3_py
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_ROOT)

import mos3_py
import boto3
from botocore.config import Config as BotoConfig
from botocore.exceptions import ClientError
from moto.server import ThreadedMotoServer

# ── Constants ────────────────────────────────────────────────────

ENDPOINT_HOST = "127.0.0.1"
ACCESS_KEY = "AKIAIO...MPLE"
SECRET_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
REGION = "us-east-1"
BUCKET = "benchmark-bucket"

# Number of warmup iterations before timing
WARMUP = 2
# Number of timed iterations (use --quick for fewer)
ITERATIONS = 10
QUICK_ITERATIONS = 3


def generate_data(size_bytes: int) -> bytes:
    """Generate deterministic pseudo-random ASCII-safe data of a given size.
    
    Uses only printable ASCII (0x20-0x7E) to avoid encoding issues between
    mos3 (which encodes strings as UTF-8) and boto3 (raw bytes).
    """
    rng = random.Random(42)
    ascii_chars = b"".join(
        bytes([i]) for i in range(0x20, 0x7F)
    )  # 95 printable ASCII chars
    result = bytearray(size_bytes)
    for i in range(size_bytes):
        result[i] = ascii_chars[rng.randint(0, len(ascii_chars) - 1)]
    return bytes(result)


def time_operation(func, *args, **kwargs):
    """Time a single function call. Returns (result, elapsed_seconds)."""
    t0 = time.perf_counter()
    result = func(*args, **kwargs)
    elapsed = time.perf_counter() - t0
    return result, elapsed


def benchmark_operation(name, mos3_fn, boto3_fn, warmup=WARMUP, iterations=ITERATIONS):
    """
    Benchmark an operation using both mos3 and boto3.

    Returns dict with mos3_ms and boto3_ms (average over iterations after warmup).
    """
    # Warmup (discard)
    for _ in range(warmup):
        mos3_fn()
    for _ in range(warmup):
        boto3_fn()

    # Timed runs — mos3
    mos3_times = []
    for _ in range(iterations):
        _, elapsed = time_operation(mos3_fn)
        mos3_times.append(elapsed)

    # Timed runs — boto3
    boto3_times = []
    for _ in range(iterations):
        _, elapsed = time_operation(boto3_fn)
        boto3_times.append(elapsed)

    mos3_avg_ms = (sum(mos3_times) / len(mos3_times)) * 1000
    boto3_avg_ms = (sum(boto3_times) / len(boto3_times)) * 1000

    return {
        "mos3_ms": mos3_avg_ms,
        "boto3_ms": boto3_avg_ms,
        "ratio": mos3_avg_ms / boto3_avg_ms if boto3_avg_ms > 0 else float("inf"),
    }


def format_size(size_str):
    """Pad size string for table alignment."""
    return f"{size_str:<10}"


def print_header():
    print()
    print(f"{'Operation':<18} {'Size':<10} {'mos3 (ms)':>10} {'boto3 (ms)':>10} {'Ratio':>8}")
    print("-" * 60)


def print_row(operation, size, result):
    ratio_str = f"{result['ratio']:.2f}x"
    print(
        f"{operation:<18} {size:<10} {result['mos3_ms']:>10.2f} {result['boto3_ms']:>10.2f} {ratio_str:>8}"
    )


def main():
    quick = "--quick" in sys.argv
    global ITERATIONS
    if quick:
        ITERATIONS = QUICK_ITERATIONS

    # ── Start moto server ────────────────────────────────────────
    port = 15002  # Different from integration test to avoid conflicts
    server = ThreadedMotoServer(port=port)
    server.start()
    print(f"Moto server running on port {port}")

    try:
        # ── Create bucket ────────────────────────────────────────
        import urllib.request
        req = urllib.request.Request(
            f"http://{ENDPOINT_HOST}:{port}/{BUCKET}", method="PUT"
        )
        urllib.request.urlopen(req)
        print(f"Created bucket: {BUCKET}")

        endpoint_url = f"http://{ENDPOINT_HOST}:{port}"

        # ── Create mos3 client ───────────────────────────────────
        mos3_client = mos3_py.client_new(
            ACCESS_KEY, SECRET_KEY, REGION, f"{ENDPOINT_HOST}:{port}", BUCKET
        )

        # ── Create boto3 client ──────────────────────────────────
        boto3_client = boto3.client(
            "s3",
            aws_access_key_id=ACCESS_KEY,
            aws_secret_access_key=SECRET_KEY,
            region_name=REGION,
            endpoint_url=endpoint_url,
            config=BotoConfig(retries={"max_attempts": 0}),
        )

        results = []

        # ── Generate test data ───────────────────────────────────
        data_1kb = generate_data(1024)          # 1 KB
        data_1mb = generate_data(1024 * 1024)   # 1 MB
        data_10mb = generate_data(10 * 1024 * 1024)  # 10 MB

        data_1kb_str = data_1kb.decode("latin-1")
        data_1mb_str = data_1mb.decode("latin-1")
        data_10mb_str = data_10mb.decode("latin-1")

        # ── Benchmark: put 1KB ───────────────────────────────────
        print("\nBenchmarking put 1KB...")
        result = benchmark_operation(
            "put",
            mos3_fn=lambda: mos3_py.client_put(
                mos3_client, "bench-1kb.bin", data_1kb_str, "application/octet-stream"
            ),
            boto3_fn=lambda: boto3_client.put_object(
                Bucket=BUCKET, Key="bench-1kb.bin", Body=data_1kb
            ),
            warmup=WARMUP, iterations=ITERATIONS,
        )
        results.append(("put", "1 KB", result))
        print_row("put", "1 KB", result)

        # ── Benchmark: put 1MB ───────────────────────────────────
        print("Benchmarking put 1MB...")
        result = benchmark_operation(
            "put",
            mos3_fn=lambda: mos3_py.client_put(
                mos3_client, "bench-1mb.bin", data_1mb_str, "application/octet-stream"
            ),
            boto3_fn=lambda: boto3_client.put_object(
                Bucket=BUCKET, Key="bench-1mb.bin", Body=data_1mb
            ),
            warmup=WARMUP, iterations=ITERATIONS,
        )
        results.append(("put", "1 MB", result))
        print_row("put", "1 MB", result)

        # ── Benchmark: put 10MB ──────────────────────────────────
        print("Benchmarking put 10MB...")
        result = benchmark_operation(
            "put",
            mos3_fn=lambda: mos3_py.client_put(
                mos3_client, "bench-10mb.bin", data_10mb_str, "application/octet-stream"
            ),
            boto3_fn=lambda: boto3_client.put_object(
                Bucket=BUCKET, Key="bench-10mb.bin", Body=data_10mb
            ),
            warmup=WARMUP, iterations=ITERATIONS,
        )
        results.append(("put", "10 MB", result))
        print_row("put", "10 MB", result)

        # ── Benchmark: get 10MB ──────────────────────────────────
        print("Benchmarking get 10MB...")
        result = benchmark_operation(
            "get",
            mos3_fn=lambda: mos3_py.client_get(mos3_client, "bench-10mb.bin"),
            boto3_fn=lambda: boto3_client.get_object(
                Bucket=BUCKET, Key="bench-10mb.bin"
            )["Body"].read(),
            warmup=WARMUP, iterations=ITERATIONS,
        )
        results.append(("get", "10 MB", result))
        print_row("get", "10 MB", result)

        # ── Benchmark: stat 10MB ─────────────────────────────────
        print("Benchmarking stat 10MB...")
        result = benchmark_operation(
            "stat",
            mos3_fn=lambda: mos3_py.client_stat(mos3_client, "bench-10mb.bin"),
            boto3_fn=lambda: boto3_client.head_object(
                Bucket=BUCKET, Key="bench-10mb.bin"
            ),
            warmup=WARMUP, iterations=ITERATIONS,
        )
        results.append(("stat", "10 MB", result))
        print_row("stat", "10 MB", result)

        # ── Benchmark: list (10 objects) ─────────────────────────
        # First, create 10 objects if not already present
        print("Setting up list benchmark (10 objects)...")
        for i in range(10):
            key = f"bench-list/obj-{i:04d}.txt"
            mos3_py.client_put(
                mos3_client, key, f"object {i}", "text/plain"
            )
        print("Benchmarking list (10 objects)...")
        result = benchmark_operation(
            "list",
            mos3_fn=lambda: mos3_py.client_list(mos3_client, "bench-list/", 20),
            boto3_fn=lambda: boto3_client.list_objects_v2(
                Bucket=BUCKET, Prefix="bench-list/", MaxKeys=20
            ),
            warmup=WARMUP, iterations=ITERATIONS,
        )
        results.append(("list", "10 objs", result))
        print_row("list", "10 objs", result)

        # ── Benchmark: multipart upload 3×5MB ────────────────────
        print("Benchmarking multipart upload 3×5MB...")

        # mos3 multipart (via subprocess Mojo helper — parses internal timing)
        mojo_bin = os.path.join(PROJECT_ROOT, ".venv", "bin", "mojo")
        bench_mojo = os.path.join(PROJECT_ROOT, "tests", "_bench_mojo.mojo")

        def _run_mojo_mp(key_suffix):
            """Run the Mojo multipart benchmark and return internal elapsed ms."""
            proc = subprocess.run(
                [mojo_bin, "run", "-I", ".", bench_mojo],
                env={**os.environ, "MOTO_PORT": str(port),
                     "BENCH_KEY": f"bench-mp-mos3-{key_suffix}", "NUM_PARTS": "3", "PART_SIZE_MB": "5"},
                capture_output=True, text=True, timeout=120,
                cwd=PROJECT_ROOT,
            )
            # Parse BENCH_MS: <milliseconds> from stdout
            for line in proc.stdout.splitlines():
                if line.startswith("BENCH_MS:"):
                    return float(line.split(":")[1].strip())
            # Fallback: parse stderr or raise
            for line in proc.stderr.splitlines():
                if line.startswith("BENCH_MS:"):
                    return float(line.split(":")[1].strip())
            raise RuntimeError(f"Mojo benchmark failed to report timing.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}")

        mos3_mp_times = []
        for i in range(WARMUP):
            _run_mojo_mp(f"warmup-{i}")
        for i in range(ITERATIONS):
            ms = _run_mojo_mp(f"timed-{i}")
            mos3_mp_times.append(ms / 1000)  # Convert ms to seconds for consistency

        # boto3 multipart
        boto3_mp_times = []
        mp_data = generate_data(3 * 5 * 1024 * 1024)  # 15 MB
        for i in range(WARMUP):
            boto3_client.put_object(
                Bucket=BUCKET, Key=f"bench-mp-boto3-warmup-{i}.bin", Body=mp_data
            )
        for i in range(ITERATIONS):
            _, elapsed = time_operation(
                lambda key=f"bench-mp-boto3-timed-{i}.bin": boto3_client.put_object(
                    Bucket=BUCKET, Key=key, Body=mp_data
                )
            )
            boto3_mp_times.append(elapsed)

        mos3_mp_avg_ms = (sum(mos3_mp_times) / len(mos3_mp_times)) * 1000
        boto3_mp_avg_ms = (sum(boto3_mp_times) / len(boto3_mp_times)) * 1000
        mp_result = {
            "mos3_ms": mos3_mp_avg_ms,
            "boto3_ms": boto3_mp_avg_ms,
            "ratio": mos3_mp_avg_ms / boto3_mp_avg_ms if boto3_mp_avg_ms > 0 else float("inf"),
        }

        print_row("multipart", "3×5MB", mp_result)

        # ── Print final summary table ────────────────────────────
        print_header()
        all_results = results + [("multipart", "3×5MB", mp_result)]
        for op, size, res in all_results:
            print_row(op, size, res)
        print("-" * 60)

        # Check if results look reasonable
        for op, size, res in all_results:
            if res["mos3_ms"] < 0:
                print(f"WARNING: {op} {size} mos3 timing is negative — measurement error")
            if res["boto3_ms"] < 0:
                print(f"WARNING: {op} {size} boto3 timing is negative — measurement error")

        print("\nBenchmark complete.")

    finally:
        server.stop()
        print("Moto server stopped.")


if __name__ == "__main__":
    main()
