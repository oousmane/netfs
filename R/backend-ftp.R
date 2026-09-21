.ftp_url <- function(con, path = "/", diagnostic = FALSE) {
  scheme <- if (con$tls) "ftp" else "ftp"
  directory <- .has_trailing_path_separator(path)
  encoded <- vapply(strsplit(sub("^/", "", .netfs_path_normalize(path)), "/", fixed = TRUE)[[1L]], curl::curl_escape, character(1))
  url <- paste0(scheme, "://", con$host, ":", con$port, "/", paste(encoded, collapse = "/"))
  if (directory && !endsWith(url, "/")) paste0(url, "/") else url
}

.ftp_handle <- function(con) {
  handle <- curl::new_handle()
  opts <- c(list(ftp_use_epsv = TRUE), con$options)
  if (!is.null(con$user)) opts$username <- con$user
  password <- .connection_password(con)
  if (!is.null(password)) opts$password <- password
  if (con$tls) opts$use_ssl <- 3L
  do.call(curl::handle_setopt, c(list(handle = handle), opts))
  handle
}

.ftp_translate <- function(e, con, path, action) {
  message <- conditionMessage(e)
  if (grepl("login denied|authentication|530", message, ignore.case = TRUE)) abort_netfs_auth(sprintf("FTP authentication to `%s` failed.", con$host))
  if (grepl("not found|550", message, ignore.case = TRUE)) abort_netfs_not_found(sprintf("Remote path `%s` was not found on `%s`.", path, con$host))
  abort_netfs_connection(sprintf("FTP %s failed on `%s`.", action, con$host), parent = e)
}

.ftp_request <- function(con, path, action, fun, handle = .ftp_handle(con)) {
  tryCatch(fun(.ftp_url(con, path), handle), error = function(e) .ftp_translate(e, con, path, action))
}

.file_download.netfs_ftp <- function(con, path, local, ...) {
  tmp <- tempfile("netfs-download-", tmpdir = dirname(fs::path_abs(local)))
  on.exit(if (fs::file_exists(tmp)) fs::file_delete(tmp), add = TRUE)
  .ftp_request(con, path, "download", function(url, handle) curl::curl_download(url, tmp, handle = handle, quiet = TRUE))
  if (fs::file_exists(local)) fs::file_delete(local)
  fs::file_move(tmp, local); invisible(local)
}

.file_upload.netfs_ftp <- function(con, local, path, ...) {
  tryCatch(curl::curl_upload(local, .ftp_url(con, path), handle = .ftp_handle(con)),
    error = function(e) .ftp_translate(e, con, path, "upload"))
  invisible(path)
}

.dir_ls.netfs_ftp <- function(con, path, ...) {
  handle <- .ftp_handle(con); curl::handle_setopt(handle, dirlistonly = TRUE)
  response <- .ftp_request(con, paste0(path, "/"), "listing",
    function(url, handle) curl::curl_fetch_memory(url, handle = handle), handle = handle)
  names <- strsplit(rawToChar(response$content), "\r?\n")[[1L]]
  vapply(names[nzchar(names)], function(x) .remote_path_join(path, x), character(1))
}

.ftp_metadata <- function(con, path) {
  # nobody = TRUE (curl's HEAD-equivalent) is a lightweight FTP SIZE/MDTM
  # query - it only succeeds for a file, never transferring file content.
  # Without it, curl_fetch_memory() on an FTP file URL downloads the whole
  # file just to check it exists (confirmed live: 18s for a 22MB file vs
  # 4s with nobody = TRUE), which made file_exists()/file_info() unusably
  # slow, or effectively hung, for large files.
  handle <- .ftp_handle(con); curl::handle_setopt(handle, nobody = TRUE)
  .ftp_request(con, path, "metadata", function(url, handle) curl::curl_fetch_memory(url, handle = handle), handle = handle)
}

.ftp_exists <- function(con, path, directory = FALSE) {
  tryCatch({
    if (directory) .dir_ls.netfs_ftp(con, path) else .ftp_metadata(con, path)
    TRUE
  }, netfs_not_found = function(e) FALSE)
}
.file_exists.netfs_ftp <- function(con, path, ...) .ftp_exists(con, path)
.dir_exists.netfs_ftp <- function(con, path, ...) .ftp_exists(con, path, TRUE)

.ftp_parse_metadata_headers <- function(response) {
  headers <- rawToChar(response$headers)
  size <- if (grepl("Content-Length:", headers, fixed = TRUE)) {
    suppressWarnings(as.numeric(sub(".*Content-Length:\\s*(\\d+).*", "\\1", headers)))
  } else NA_real_
  date_match <- regmatches(headers, regexpr("Last-Modified:\\s*[A-Za-z]+, [^\r\n]+", headers))
  modification_time <- if (length(date_match)) {
    as.POSIXct(sub("Last-Modified:\\s*[A-Za-z]+, ", "", date_match), format = "%d %b %Y %H:%M:%S", tz = "GMT")
  } else as.POSIXct(NA)
  list(size = size, modification_time = modification_time)
}

.file_info.netfs_ftp <- function(con, path, ...) {
  # A file's metadata is available cheaply (see .ftp_metadata()); a
  # directory's is not (the same nobody = TRUE request fails outright for
  # one, confirmed live), so directories fall back to existence only.
  response <- tryCatch(.ftp_metadata(con, path), netfs_not_found = function(e) NULL)
  if (!is.null(response)) {
    meta <- .ftp_parse_metadata_headers(response)
    return(.new_remote_info(path, "file", meta$size, meta$modification_time))
  }
  if (!.dir_exists.netfs_ftp(con, path)) abort_netfs_not_found(sprintf("Remote path `%s` was not found.", path))
  .new_remote_info(path, "directory")
}

.ftp_quote <- function(con, command, path, action) {
  handle <- .ftp_handle(con); curl::handle_setopt(handle, quote = sprintf("%s %s", command, path), nobody = TRUE)
  .ftp_request(con, "/", action, function(url, handle) curl::curl_fetch_memory(url, handle = handle), handle = handle)
  invisible(path)
}
.dir_create.netfs_ftp <- function(con, path, ...) .ftp_quote(con, "MKD", path, "directory creation")
.dir_delete.netfs_ftp <- function(con, path, ...) .ftp_quote(con, "RMD", path, "directory deletion")
.file_delete.netfs_ftp <- function(con, path, ...) .ftp_quote(con, "DELE", path, "file deletion")
.file_move.netfs_ftp <- function(con, path, new_path, ...) {
  handle <- .ftp_handle(con); curl::handle_setopt(handle, quote = c(sprintf("RNFR %s", path), sprintf("RNTO %s", new_path)), nobody = TRUE)
  .ftp_request(con, "/", "rename", function(url, handle) curl::curl_fetch_memory(url, handle = handle), handle = handle); invisible(new_path)
}
.file_copy.netfs_ftp <- function(con, path, new_path, ...) abort_netfs_unsupported("Server-side file copy is not supported by the FTP backend.", operation = "file_copy")
