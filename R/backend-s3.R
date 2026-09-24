# Thin adapter over s3fs. Two things shape this file:
#
# 1. Every s3fs::s3_*() convenience function is a wrapper around a single
#    process-global cached S3FileSystem instance (s3_file_system()'s own
#    cache) - calling it from two different netfs connections would have
#    the second one silently clobber the first's credentials. Instead,
#    .s3_client() builds a fresh s3fs::S3FileSystem R6 object straight
#    from `con`'s own fields on every call - the same "rebuild, don't
#    cache" approach .ftp_handle() already uses for curl handles - and
#    every method here calls the R6 object's own methods directly
#    (confirmed live against local MinIO), never the s3_*() wrappers.
#
# 2. paws (the AWS SDK s3fs itself is built on) throws conditions classed
#    by HTTP status - http_404, http_403, http_401 - so failures are
#    caught by class, not by matching message text the way the other
#    backends have to.

.s3_client <- function(con) {
  .require_s3fs()
  args <- c(list(
    aws_access_key_id = con$user,
    aws_secret_access_key = .connection_password(con),
    region_name = con$region_name,
    profile_name = con$profile_name,
    endpoint = con$endpoint
  ), con$options)
  do.call(s3fs::S3FileSystem$new, args)
}

# s3fs's own path convention is "bucket/key/...", with no leading slash;
# netfs's is "/key/..." relative to the connection's one bucket.
.s3_path <- function(con, path) {
  rel <- sub("^/+", "", path)
  if (nzchar(rel)) paste0(con$bucket, "/", rel) else con$bucket
}

# file_copy()/file_move() specifically dispatch on their own is_uri() (a
# literal "s3://" prefix check) to decide between an S3-to-S3 copy, a
# download, or an upload - confirmed live that a bare "bucket/key" string
# (which every other method here accepts and works with) matches none of
# its three branches, so the call reports success but silently does
# nothing at all.
.s3_uri <- function(con, path) paste0("s3://", .s3_path(con, path))

# dir_info()/file_info() return a bare `key` (no bucket prefix at all);
# dir_ls() returns a full "s3://bucket/key" uri instead - both end up
# here so either shape converts to a netfs path the same way.
.s3_to_netfs_path <- function(con, key) {
  key <- sub("^s3://", "", key)
  key <- sub("/+$", "", key)
  bucket_prefix <- paste0(con$bucket, "/")
  if (startsWith(key, bucket_prefix)) key <- substring(key, nchar(bucket_prefix) + 1L)
  else if (identical(key, con$bucket)) key <- ""
  .netfs_path_normalize(key)
}

.s3_run <- function(con, expr, path = NULL) {
  # http_403, not http_401, is what bad credentials actually produce here
  # (confirmed live: a wrong secret key against MinIO comes back as 403) -
  # AWS S3's API uses 403 Forbidden for SignatureDoesNotMatch and
  # InvalidAccessKeyId alike, unlike most other protocols' use of 401 for
  # "who are you" versus 403 for "I know who you are, but no". http_401 is
  # still handled below in case some S3-compatible service does use it.
  #
  # The translated abort_netfs_*() call must happen after tryCatch() has
  # fully returned, not inside a handler - confirmed live that s3fs's own
  # future.apply-based methods (e.g. file_info()) leave some handler-stack
  # state active during their "cancel other iterations" cleanup on error,
  # so a new condition thrown from inside a handler here gets re-caught by
  # this same tryCatch's own generic error= handler instead of escaping
  # to the caller as intended.
  outcome <- tryCatch(
    list(ok = TRUE, value = expr),
    http_404 = function(e) list(ok = FALSE, kind = "not_found", detail = e),
    http_403 = function(e) list(ok = FALSE, kind = "permission", detail = e),
    http_401 = function(e) list(ok = FALSE, kind = "auth", detail = e),
    error = function(e) list(ok = FALSE, kind = "generic", detail = e)
  )
  if (outcome$ok) return(outcome$value)
  switch(outcome$kind,
    not_found = abort_netfs_not_found(sprintf("Remote path `%s` was not found in bucket `%s`.", path %||% "", con$bucket), parent = outcome$detail),
    permission = abort_netfs_permission(sprintf("S3 operation in bucket `%s` was denied.", con$bucket), parent = outcome$detail),
    auth = abort_netfs_auth(sprintf("S3 authentication for bucket `%s` failed.", con$bucket), parent = outcome$detail),
    generic = abort_netfs(sprintf("S3 operation in bucket `%s` failed: %s", con$bucket, conditionMessage(outcome$detail)), "netfs_backend_error", parent = outcome$detail)
  )
}

.s3_list <- function(con, path, recurse = FALSE) {
  .s3_run(con, .s3_client(con)$dir_info(.s3_path(con, path), recurse = recurse), path = path)
}

.dir_ls.netfs_s3 <- function(con, path, ...) {
  info <- .s3_list(con, path)
  if (!nrow(info)) return(character())
  vapply(info$key, function(k) .s3_to_netfs_path(con, k), character(1), USE.NAMES = FALSE)
}

.dir_info.netfs_s3 <- function(con, path, ...) {
  info <- .s3_list(con, path)
  if (!nrow(info)) return(.new_remote_info(character()))
  paths <- vapply(info$key, function(k) .s3_to_netfs_path(con, k), character(1), USE.NAMES = FALSE)
  .new_remote_info(paths, as.character(info$type), as.numeric(info$size), info$last_modified)
}

.file_exists.netfs_s3 <- function(con, path, ...) {
  isTRUE(.s3_run(con, .s3_client(con)$file_exists(.s3_path(con, path)), path = path))
}

.dir_exists.netfs_s3 <- function(con, path, ...) {
  if (identical(path, "/")) {
    # No bucket-existence check here: s3fs's own is_bucket() needs
    # s3:ListAllMyBuckets, which a connection correctly scoped to just
    # this one bucket often won't have. A listing attempt (even an empty
    # one) is a better signal - it fails the same way a real operation
    # would, rather than over-requiring a permission actual use doesn't
    # need.
    .s3_list(con, "/")
    return(TRUE)
  }
  isTRUE(.s3_run(con, .s3_client(con)$dir_exists(.s3_path(con, path)), path = path))
}

.file_info.netfs_s3 <- function(con, path, ...) {
  info <- .s3_run(con, .s3_client(con)$file_info(.s3_path(con, path)), path = path)
  .new_remote_info(path, as.character(info$type), as.numeric(info$size), info$last_modified)
}

.dir_create.netfs_s3 <- function(con, path, ...) {
  .s3_run(con, .s3_client(con)$dir_create(.s3_path(con, path)), path = path)
  invisible(path)
}

.dir_delete.netfs_s3 <- function(con, path, ...) {
  # S3 has no atomic "fail if non-empty" primitive (unlike POSIX rmdir or
  # FTP's RMD) - dir_delete() in s3fs is unconditionally recursive. A
  # cheap listing first keeps this call just as safe as every other
  # backend's plain (non-recursive) delete. netfs's own dir_delete(recurse
  # = TRUE) already empties a directory itself, one entry at a time,
  # before ever calling this method - so by the time that path reaches
  # here, the check below naturally finds nothing left to object to.
  if (length(.dir_ls.netfs_s3(con, path))) {
    abort_netfs(sprintf("Remote directory `%s` is not empty.", path), "netfs_backend_error")
  }
  .s3_run(con, .s3_client(con)$dir_delete(.s3_path(con, path)), path = path)
  invisible(path)
}

.file_delete.netfs_s3 <- function(con, path, ...) {
  .s3_run(con, .s3_client(con)$file_delete(.s3_path(con, path)), path = path)
  invisible(path)
}

.file_copy.netfs_s3 <- function(con, path, new_path, ...) {
  .s3_run(con, .s3_client(con)$file_copy(.s3_uri(con, path), .s3_uri(con, new_path), overwrite = TRUE), path = path)
  invisible(new_path)
}

.file_move.netfs_s3 <- function(con, path, new_path, ...) {
  .s3_run(con, .s3_client(con)$file_move(.s3_uri(con, path), .s3_uri(con, new_path), overwrite = TRUE), path = path)
  invisible(new_path)
}

.file_download.netfs_s3 <- function(con, path, local, ...) {
  .s3_run(con, .s3_client(con)$file_download(.s3_path(con, path), local, overwrite = TRUE), path = path)
  invisible(local)
}

.file_upload.netfs_s3 <- function(con, local, path, ...) {
  .s3_run(con, .s3_client(con)$file_upload(local, .s3_path(con, path), overwrite = TRUE), path = path)
  invisible(path)
}
