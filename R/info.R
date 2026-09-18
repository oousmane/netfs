#' Retrieve file metadata
#' @inheritParams dir_ls
#' @return Locally, the result of [fs::file_info()]. Remotely, a tibble with
#'   `path`, `type`, `size`, and `modification_time` columns.
#' @family filesystem operations
#' @export
file_info <- function(path, con = NULL, ...) {
  if (is.null(con)) return(fs::file_info(path, ...))
  .check_connection(con); .file_info(con, .netfs_path_normalize(path), ...)
}

.new_remote_info <- function(path, type = NA_character_, size = NA_real_, modification_time = as.POSIXct(NA)) {
  tibble::tibble(path = path, type = type, size = as.numeric(size),
    modification_time = as.POSIXct(modification_time, origin = "1970-01-01", tz = "UTC"))
}
