new_netfs_connection <- function(backend, fields) {
  .check_scalar_character(backend, "backend")
  structure(fields, class = c(paste0("netfs_", backend), "netfs_connection"))
}

is_netfs_connection <- function(x) inherits(x, "netfs_connection")

#' Print a netfs connection
#' @param x A netfs connection.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
print.netfs_connection <- function(x, ...) {
  cat(sprintf("<%s>\n", class(x)[[1L]]))
  visible <- switch(class(x)[[1L]],
    netfs_ftp = c("host", "user", "port", "tls"),
    netfs_ssh = c("host", "user", "port", "identity_file"),
    netfs_smb = c("host", "share", "user", "domain"),
    netfs_webdav = c("url", "user"),
    netfs_s3 = c("bucket", "user", "region_name", "endpoint"),
    character()
  )
  for (name in visible) {
    value <- x[[name]]
    if (!is.null(value)) {
      display <- if (is.logical(value)) tolower(as.character(value)) else as.character(value)
      cat(sprintf("%s: %s\n", name, display))
    }
  }
  invisible(x)
}
