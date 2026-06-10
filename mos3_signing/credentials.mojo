"""
S3Credentials and signing-related types.
Mirrors bun_s3_signing::credentials module.
"""
from mos3_signing.error import S3Error


@fieldwise_init
struct S3Credentials(Movable, Copyable, ImplicitlyCopyable):
    """AWS S3 credentials and connection configuration."""
    var access_key_id: String
    var secret_access_key: String
    var region: String          # e.g. "us-east-1"
    var endpoint: String        # e.g. "s3.amazonaws.com"
    var bucket: String
    var session_token: String   # empty if not using temporary credentials
    var virtual_hosted_style: Bool  # true: bucket.s3.amazonaws.com
    var insecure_http: Bool     # use http:// instead of https://

    @staticmethod
    def create(
        access_key_id: String,
        secret_access_key: String,
        region: String = "us-east-1",
        endpoint: String = "s3.amazonaws.com",
        bucket: String = "",
        session_token: String = "",
        virtual_hosted_style: Bool = True,
        insecure_http: Bool = False,
    ) -> Self:
        return Self(
            access_key_id=access_key_id,
            secret_access_key=secret_access_key,
            region=region,
            endpoint=endpoint,
            bucket=bucket,
            session_token=session_token,
            virtual_hosted_style=virtual_hosted_style,
            insecure_http=insecure_http,
        )


@fieldwise_init
struct SignOptions(Movable, Copyable):
    """Options for signing an S3 request."""
    var path: String
    var method: String           # "GET", "PUT", "HEAD", "DELETE"
    var search_params: String    # query string (without leading '?')
    var content_hash: String     # SHA256 of body, or "" for empty-payload hash
    var content_type: String
    var content_encoding: String
    var content_disposition: String
    var request_payer: Bool

    @staticmethod
    def create(
        path: String,
        method: String = "GET",
        search_params: String = "",
        content_hash: String = "",
        content_type: String = "",
        content_encoding: String = "",
        content_disposition: String = "",
        request_payer: Bool = False,
    ) -> Self:
        return Self(
            path=path,
            method=method,
            search_params=search_params,
            content_hash=content_hash,
            content_type=content_type,
            content_encoding=content_encoding,
            content_disposition=content_disposition,
            request_payer=request_payer,
        )


@fieldwise_init
struct SignResult(Movable):
    """Result of signing an S3 request."""
    var url: String
    var authorization_header: String      # "AWS4-HMAC-SHA256 Credential=..."
    var amz_date: String                  # x-amz-date header value
    var content_sha256: String            # x-amz-content-sha256 header value
    var security_token_header: String     # x-amz-security-token (empty if no token)
