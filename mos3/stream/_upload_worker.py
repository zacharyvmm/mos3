"""
Python worker for concurrent S3 multipart part uploads.
Used by mos3.stream.upload to upload parts in parallel threads.
"""
import http.client
import time
from urllib.parse import urlparse


def upload_part(url, auth_header, amz_date, content_sha256,
                security_token, body_bytes, part_number, retries):
    """Upload a single S3 part with retry logic.

    Returns (etag, part_number) tuple on success.
    Raises exception after all retries exhausted.
    """
    parsed = urlparse(url)
    host = parsed.hostname
    port = parsed.port or (443 if parsed.scheme == 'https' else 80)
    path_and_query = parsed.path
    if parsed.query:
        path_and_query += '?' + parsed.query

    last_exc = Exception('unknown error')
    for attempt in range(retries + 1):
        try:
            conn = http.client.HTTPConnection(host, port, timeout=30)
            headers = {
                'Authorization': auth_header,
                'x-amz-content-sha256': content_sha256,
                'x-amz-date': amz_date,
            }
            if security_token:
                headers['x-amz-security-token'] = security_token

            conn.request('PUT', path_and_query, body=body_bytes, headers=headers)
            resp = conn.getresponse()
            if resp.status == 200:
                etag = resp.getheader('ETag', '')
                conn.close()
                return (etag, part_number)
            # Read body for error info, but don't fail on read errors
            try:
                resp.read()
            except Exception:
                pass
            conn.close()
            raise Exception(
                'Part {} upload failed: HTTP {}'.format(part_number, resp.status)
            )
        except Exception as e:
            last_exc = e
            if attempt < retries:
                time.sleep(2 ** attempt)  # exponential backoff: 1, 2, 4, 8...

    raise last_exc
