"""Start moto server, create test buckets, then keep running."""
from moto.server import ThreadedMotoServer
import urllib.request
import signal

port = 15001
server = ThreadedMotoServer(port=port)
server.start()
print(f"MOTO_READY on port {port}", flush=True)

# Create test buckets
for bucket in ["test-bucket", "test-bucket-copy"]:
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/{bucket}", method="PUT"
    )
    try:
        urllib.request.urlopen(req)
        print(f"Created bucket: {bucket}", flush=True)
    except Exception as e:
        print(f"Bucket {bucket} may already exist: {e}", flush=True)

signal.pause()
