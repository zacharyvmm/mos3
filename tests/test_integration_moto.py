"""
Integration test runner using moto S3 mock server.
Usage: python3 tests/test_integration_moto.py
"""
import subprocess
import sys
import os
import urllib.request
from moto.server import ThreadedMotoServer


def main():
    port = 15001
    server = ThreadedMotoServer(port=port)
    server.start()
    print(f"Moto server running on port {port}")

    try:
        # Pre-create the test bucket
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/test-bucket", method="PUT"
        )
        urllib.request.urlopen(req)
        print("Created test-bucket")

        mojo = os.path.join(os.path.dirname(__file__), "..", ".venv", "bin", "mojo")
        result = subprocess.run(
            [mojo, "run", "-I", ".", "tests/test_integration_moto.mojo"],
            env={**os.environ, "MOTO_PORT": str(port)},
            capture_output=True,
            text=True,
            timeout=120,
            cwd=os.path.join(os.path.dirname(__file__), ".."),
        )
        print(result.stdout)
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            sys.exit(1)
    finally:
        server.stop()


if __name__ == "__main__":
    main()
