.check_scalar_character <- function(x, arg, allow_empty = FALSE) {
  if (!is.character(x) || length(x) != 1L || is.na(x) ||
      (!allow_empty && !nzchar(x))) {
    rlang::abort(sprintf("`%s` must be a single non-missing%s character value.", arg,
      if (allow_empty) "" else " non-empty"), class = "netfs_validation_error")
  }
  invisible(x)
}

.check_optional_scalar_character <- function(x, arg) {
  if (!is.null(x)) .check_scalar_character(x, arg)
  invisible(x)
}

.check_scalar_logical <- function(x, arg) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    rlang::abort(sprintf("`%s` must be TRUE or FALSE.", arg), class = "netfs_validation_error")
  }
  invisible(x)
}

.check_port <- function(x) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x != as.integer(x) || x < 1 || x > 65535) {
    rlang::abort("`port` must be an integer between 1 and 65535.", class = "netfs_validation_error")
  }
  as.integer(x)
}

.check_connection <- function(con) {
  if (!is_netfs_connection(con)) {
    rlang::abort("`con` must be a connection created by ftp(), ssh(), or smb().",
      class = "netfs_validation_error")
  }
  invisible(con)
}
