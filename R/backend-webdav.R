# Thin adapter over the webdav package. Two verified quirks in that package
# drive most of the design here:
#
# 1. Its error handling is inconsistent by function. webdav_copy_file(),
#    webdav_download_file(), and webdav_create_directory() throw a real R
#    condition on failure. webdav_upload_file(), webdav_list_files(), and
#    webdav_delete_resource() never throw for a network or HTTP-status
#    failure - they emit a warning and return FALSE/NULL instead. Confirmed
#    live against a local WsgiDAV server (e.g. deleting a nonexistent
#    resource returns FALSE with a warning, not an error). .webdav_run()
#    handles both shapes uniformly.
#
# 2. webdav_list_files() always drops the first PROPFIND response via
#    slice_tail(n = -1), on the assumption it's always the queried
#    collection's own entry. That's true for a directory, but for a PLAIN
#    FILE - which still answers PROPFIND with itself as the only entry -
#    it means the one real row gets silently dropped, indistinguishable
#    from an empty directory (confirmed live: both return 0 rows, and
#    depth = 0 doesn't help either, for the same reason). So a specific
#    path's own type/existence can only be determined by listing its
#    *parent* and matching a child entry by name, never by listing the
#    path itself.

.webdav_relpath <- function(path) {
  path <- sub("^/+", "", path)
  if (!nzchar(path)) NULL else path
}

.webdav_url_path <- function(url) {
  path <- sub("^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+", "", url)
  if (!nzchar(path)) "/" else path
}

# Every href the server returns is absolute from the WebDAV *server's* own
# root, regardless of what base_url/folder_path was queried with (confirmed
# live against a local WsgiDAV server) - so this always strips the
# connection's own URL path prefix, not whatever path happened to be
# listed. RFC 4918 permits <href> to be either a relative path or a full
# absolute URL (scheme + host included), server's choice; confirmed live
# that IT Hit's .NET WebDAV Server (unlike WsgiDAV) uses the latter, so
# any scheme+host present is stripped first, before the connection's own
# path-prefix stripping runs on what's left.
.webdav_to_netfs_path <- function(con, href) {
  href <- sub("/+$", "", href)
  href <- sub("^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+", "", href)
  prefix <- sub("/+$", "", .webdav_url_path(con$url))
  if (nzchar(prefix) && startsWith(href, prefix)) href <- substring(href, nchar(prefix) + 1L)
  .netfs_path_normalize(href)
}

.webdav_parse_time <- function(x) {
  as.POSIXct(x, format = "%a, %d %b %Y %H:%M:%S", tz = "GMT")
}

.webdav_translate <- function(con, detail, path = NULL) {
  detail <- detail %||% "request failed"
  if (grepl("HTTP 404", detail, fixed = TRUE)) {
    abort_netfs_not_found(sprintf("Remote path `%s` was not found on `%s`.", path %||% "", con$url), detail = detail)
  }
  if (grepl("HTTP 401", detail, fixed = TRUE)) {
    abort_netfs_auth(sprintf("WebDAV authentication to `%s` failed.", con$url), detail = detail)
  }
  if (grepl("HTTP 403", detail, fixed = TRUE)) {
    abort_netfs_permission(sprintf("WebDAV operation on `%s` was denied.", con$url), detail = detail)
  }
  # Confirmed live: httr2/curl phrase a refused connection and a DNS
  # failure this way (not as an "HTTP ###" status - the request never
  # reached a server to get one).
  if (grepl("could not connect|could not resolve|timed out|connection refused", detail, ignore.case = TRUE)) {
    abort_netfs_connection(sprintf("Could not connect to WebDAV server `%s`.", con$url), detail = detail)
  }
  abort_netfs(sprintf("WebDAV operation on `%s` failed: %s", con$url, detail), "netfs_backend_error")
}

# Runs one webdav::webdav_*() call, capturing either a thrown condition or a
# warning (see the file banner) as `detail`, and translating a failure -
# by either path - into netfs's own condition classes. `ok` decides what a
# successful result looks like; the default (non-NULL, not FALSE) covers
# every case here, including a validly empty listing tibble.
.webdav_run <- function(con, expr, path = NULL, ok = function(v) !is.null(v) && !isFALSE(v)) {
  detail <- NULL
  value <- tryCatch(
    withCallingHandlers(expr, warning = function(w) {
      detail <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }),
    error = function(e) {
      detail <<- conditionMessage(e)
      NULL
    }
  )
  if (!ok(value)) .webdav_translate(con, detail, path)
  value
}

.webdav_list <- function(con, path) {
  .webdav_run(con, webdav::webdav_list_files(
    base_url = con$url, folder_path = .webdav_relpath(path),
    username = con$user %||% "", password = .connection_password(con) %||% ""
  ), path = path)
}

.dir_ls.netfs_webdav <- function(con, path, ...) {
  result <- .webdav_list(con, path)
  if (!nrow(result)) return(character())
  vapply(result$full_path, function(h) .webdav_to_netfs_path(con, h), character(1), USE.NAMES = FALSE)
}

.dir_info.netfs_webdav <- function(con, path, ...) {
  result <- .webdav_list(con, path)
  if (!nrow(result)) return(.new_remote_info(character()))
  paths <- vapply(result$full_path, function(h) .webdav_to_netfs_path(con, h), character(1), USE.NAMES = FALSE)
  type <- ifelse(result$is_folder, "directory", "file")
  size <- ifelse(result$is_folder, NA_real_, result$content_length)
  .new_remote_info(paths, type, size, .webdav_parse_time(result$last_modified))
}

# Lists the target's *parent* and matches a child by basename - see the file
# banner for why listing the target itself can't distinguish a file from an
# empty directory.
.webdav_stat <- function(con, path) {
  if (identical(path, "/")) {
    .dir_info(con, "/") # only to let a real auth/connection failure propagate
    return(list(exists = TRUE, type = "directory", size = NA_real_, mtime = as.POSIXct(NA)))
  }
  info <- tryCatch(.dir_info(con, .remote_path_dirname(path)), netfs_not_found = function(e) NULL)
  if (is.null(info)) return(list(exists = FALSE))
  name <- .remote_path_basename(path)
  idx <- which(vapply(as.character(info$path), .remote_path_basename, character(1)) == name)
  if (!length(idx)) return(list(exists = FALSE))
  list(exists = TRUE, type = as.character(info$type[[idx[1L]]]),
    size = info$size[[idx[1L]]], mtime = info$modification_time[[idx[1L]]])
}

.file_exists.netfs_webdav <- function(con, path, ...) {
  stat <- .webdav_stat(con, path)
  isTRUE(stat$exists) && identical(stat$type, "file")
}

.dir_exists.netfs_webdav <- function(con, path, ...) {
  stat <- .webdav_stat(con, path)
  isTRUE(stat$exists) && identical(stat$type, "directory")
}

.file_info.netfs_webdav <- function(con, path, ...) {
  stat <- .webdav_stat(con, path)
  if (!isTRUE(stat$exists)) abort_netfs_not_found(sprintf("Remote path `%s` was not found.", path))
  .new_remote_info(path, stat$type, stat$size, stat$mtime)
}

.dir_create.netfs_webdav <- function(con, path, ...) {
  .webdav_run(con, webdav::webdav_create_directory(
    base_url = con$url, folder_path = .webdav_relpath(path),
    username = con$user %||% "", password = .connection_password(con) %||% ""
  ), path = path)
  invisible(path)
}

.dir_delete.netfs_webdav <- function(con, path, ...) {
  .webdav_run(con, webdav::webdav_delete_resource(
    base_url = con$url, resource_path = .webdav_relpath(path),
    username = con$user %||% "", password = .connection_password(con) %||% ""
  ), path = path)
  invisible(path)
}

.file_delete.netfs_webdav <- function(con, path, ...) {
  .webdav_run(con, webdav::webdav_delete_resource(
    base_url = con$url, resource_path = .webdav_relpath(path),
    username = con$user %||% "", password = .connection_password(con) %||% ""
  ), path = path)
  invisible(path)
}

.file_copy.netfs_webdav <- function(con, path, new_path, ...) {
  .webdav_run(con, webdav::webdav_copy_file(
    base_url = con$url, from_path = .webdav_relpath(path), to_path = .webdav_relpath(new_path),
    username = con$user %||% "", password = .connection_password(con) %||% ""
  ), path = path)
  invisible(new_path)
}

.file_move.netfs_webdav <- function(con, path, new_path, ...) {
  # No native MOVE is exposed by the webdav package (only COPY + DELETE),
  # so this is a copy followed by deleting the source - not atomic: if the
  # delete fails, both the source and the copy are left behind rather than
  # neither.
  .file_copy.netfs_webdav(con, path, new_path)
  .webdav_run(con, webdav::webdav_delete_resource(
    base_url = con$url, resource_path = .webdav_relpath(path),
    username = con$user %||% "", password = .connection_password(con) %||% ""
  ), path = path)
  invisible(new_path)
}

.file_download.netfs_webdav <- function(con, path, local, ...) {
  # webdav_download_file() always names the local file after the remote
  # basename, into a directory - it can't target an exact local path with a
  # different name. Download into a scratch directory first, then move to
  # the exact `local` path requested, the same way the SSH/FTP backends
  # stage a download before placing it.
  tmpdir <- tempfile("netfs-webdav-dl-")
  fs::dir_create(tmpdir)
  on.exit(if (fs::dir_exists(tmpdir)) fs::dir_delete(tmpdir), add = TRUE)
  .webdav_run(con, webdav::webdav_download_file(
    base_url = con$url, file_path = .webdav_relpath(path), destination_path = tmpdir,
    username = con$user %||% "", password = .connection_password(con) %||% ""
  ), path = path)
  downloaded <- fs::path(tmpdir, .remote_path_basename(path))
  if (fs::file_exists(local)) fs::file_delete(local)
  fs::file_move(downloaded, local)
  invisible(local)
}

.file_upload.netfs_webdav <- function(con, local, path, ...) {
  # Symmetric constraint: webdav_upload_file() always uses the *local*
  # file's own basename, so a destination path whose name doesn't match
  # `local`'s needs a follow-up rename via copy + delete (see
  # .file_move.netfs_webdav()), the only rename primitive available.
  remote_dir <- .remote_path_dirname(path)
  target_name <- .remote_path_basename(path)
  local_name <- as.character(fs::path_file(local))
  .webdav_run(con, webdav::webdav_upload_file(
    base_url = con$url, local_path = local, server_path = .webdav_relpath(remote_dir),
    username = con$user %||% "", password = .connection_password(con) %||% ""
  ), path = path)
  if (!identical(local_name, target_name)) {
    .file_move.netfs_webdav(con, .remote_path_join(remote_dir, local_name), path)
  }
  invisible(path)
}
