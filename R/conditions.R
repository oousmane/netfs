abort_netfs <- function(message, class = NULL, ..., call = rlang::caller_env()) {
  rlang::abort(message, class = c(class, "netfs_error"), ..., call = call)
}
abort_netfs_auth <- function(message, ...) abort_netfs(message, "netfs_auth_error", ...)
abort_netfs_not_found <- function(message, ...) abort_netfs(message, "netfs_not_found", ...)
abort_netfs_permission <- function(message, ...) abort_netfs(message, "netfs_permission_error", ...)
abort_netfs_connection <- function(message, ...) abort_netfs(message, "netfs_connection_error", ...)
abort_netfs_timeout <- function(message, ...) abort_netfs(message, "netfs_timeout", ...)
abort_netfs_backend_unavailable <- function(message, ...) abort_netfs(message, "netfs_backend_unavailable", ...)
abort_netfs_unsupported <- function(message, ...) abort_netfs(message, "netfs_unsupported", ...)

.redact_text <- function(x, redact) {
  for (secret in redact[nzchar(redact)]) x <- gsub(secret, "<redacted>", x, fixed = TRUE)
  x
}

.netfs_backend_name <- function(con) {
  switch(class(con)[[1L]], netfs_ssh = "SSH", netfs_ftp = "FTP", netfs_smb = "SMB", class(con)[[1L]])
}

.abort_netfs_op_unsupported <- function(con, operation, detail = NULL) {
  message <- sprintf("%s() is not supported by the %s backend.", operation, .netfs_backend_name(con))
  if (!is.null(detail)) message <- paste0(message, " ", detail)
  abort_netfs_unsupported(message, operation = operation)
}
