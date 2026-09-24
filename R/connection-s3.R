.require_s3fs <- function() {
  if (requireNamespace("s3fs", quietly = TRUE)) return(invisible(TRUE))
  abort_netfs_backend_unavailable(
    "S3 connections require the s3fs package. Install it first.",
    command = "s3fs"
  )
}

#' Create an S3 connection description
#'
#' A connection is scoped to one bucket, the same way [smb()] is scoped to
#' one share - paths are always relative to that bucket's own key
#' namespace. Support is provided by the s3fs package, used through its
#' underlying `S3FileSystem` object directly rather than its convenience
#' functions, which share one connection process-wide; a fresh client is
#' built locally for every call, the same way [ftp()] does. Construction
#' doesn't contact AWS.
#' @param bucket Bucket name.
#' @param aws_access_key_id Optional access key id. Maps to the
#'   connection's stored username - see [set_creds()].
#' @param aws_secret_access_key Optional secret access key. When supplied,
#'   it is written to the selected `keyring` credential store and is not
#'   retained in the connection.
#' @param region_name Optional AWS region.
#' @param endpoint Optional endpoint URL, for an S3-compatible service
#'   other than AWS (e.g. MinIO).
#' @param profile_name Optional named profile to read credentials from,
#'   instead of `aws_access_key_id`/`aws_secret_access_key`.
#' @param ... Backend options, passed through to
#'   `s3fs::S3FileSystem$new()` (for example `s3_force_path_style` for
#'   an S3-compatible service that needs it, or `anonymous = TRUE`).
#' @return A `netfs_s3` connection.
#' @family connection constructors
#' @examples
#' \dontrun{
#' s3("my-bucket", region_name = "us-east-1")
#' }
#' @export
s3 <- function(bucket, aws_access_key_id = NULL, aws_secret_access_key = NULL,
               region_name = NULL, endpoint = NULL, profile_name = NULL, ...) {
  .require_s3fs()
  .check_scalar_character(bucket, "bucket")
  .check_optional_scalar_character(aws_access_key_id, "aws_access_key_id")
  .check_optional_scalar_character(aws_secret_access_key, "aws_secret_access_key")
  .check_optional_scalar_character(region_name, "region_name")
  .check_optional_scalar_character(endpoint, "endpoint")
  .check_optional_scalar_character(profile_name, "profile_name")
  con <- new_netfs_connection("s3", list(host = bucket, bucket = bucket, user = aws_access_key_id,
    region_name = region_name, endpoint = endpoint, profile_name = profile_name, options = list(...)))
  if (!is.null(aws_secret_access_key)) set_creds(con, aws_secret_access_key)
  con
}
