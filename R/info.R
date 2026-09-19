#' Retrieve file metadata
#' @param path One or more local or remote paths.
#' @inheritParams dir_ls
#' @return Locally, the result of [fs::file_info()]. Remotely, a tibble with
#'   one row per element of `path` and `path`, `type`, `size`, and
#'   `modification_time` columns, typed like their [fs::file_info()]
#'   counterparts (`path` an `fs_path`, `type` a factor of
#'   [fs::file_info()]'s levels, `size` an `fs_bytes`). Backends that cannot
#'   determine a value report `NA`; a remote `type` string outside the known
#'   levels also reports `NA`.
#' @family filesystem operations
#' @export
file_info <- function(path, con = NULL, ...) {
  if (is.null(con)) return(fs::file_info(path, ...))
  .check_connection(con)
  if (!length(path)) return(.new_remote_info(character()))
  rows <- lapply(path, function(p) .file_info(con, .netfs_path_normalize(p), ...))
  do.call(rbind, rows)
}

.remote_file_type_levels <- c("any", "block_device", "character_device", "directory", "FIFO", "symlink", "file", "socket")

.new_remote_info <- function(path, type = NA_character_, size = NA_real_, modification_time = as.POSIXct(NA)) {
  tibble::tibble(path = fs::as_fs_path(path), type = factor(type, levels = .remote_file_type_levels),
    size = fs::as_fs_bytes(size),
    modification_time = as.POSIXct(modification_time, origin = "1970-01-01", tz = "UTC"))
}
