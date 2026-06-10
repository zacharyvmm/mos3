"""
S3Error type and signing error codes.
Mirrors bun_s3_signing::error module — pure Mojo, no Python deps.
"""


@fieldwise_init
struct S3Error(Movable, Copyable, Writable):
    """S3 error with code and message (both owned Strings)."""
    var code: String
    var message: String

    def __init__(out self):
        self.code = "UnknownError"
        self.message = "An unexpected error has occurred"

    def write_to(self, mut writer: Some[Writer]):
        writer.write("S3Error(", self.code, ": ", self.message, ")")


def get_sign_error_message(code: String) -> String:
    """Get human-readable message for a signing error code."""
    if code == "MissingCredentials":
        return "Missing required S3 credentials"
    if code == "InvalidMethod":
        return "Invalid HTTP method for S3 request"
    if code == "InvalidPath":
        return "Invalid S3 object path"
    if code == "InvalidEndpoint":
        return "Invalid S3 endpoint URL"
    if code == "InvalidSessionToken":
        return "Invalid S3 session token"
    if code == "SignError":
        return "Failed to sign S3 request"
    return "Unknown signing error"
