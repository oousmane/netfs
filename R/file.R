#' Test whether files exist
#' @inheritParams dir_ls
#' @return A logical vector.
#' @family filesystem operations
#' @export
file_exists <- function(path, con = NULL) {
  if (is.null(con)) return(fs::file_exists(path))
  .check_connection(con); vapply(path, function(x) .file_exists(con, .netfs_path_normalize(x)), logical(1))
}

#' Delete a file
#' @inheritParams dir_ls
#' @return The path, invisibly.
#' @family filesystem operations
#' @export
file_delete <- function(path, con = NULL, ...) {
  if (is.null(con)) return(fs::file_delete(path, ...))
  .check_connection(con); .file_delete(con, .netfs_path_normalize(path), ...)
}

#' Copy a file within one filesystem
#' @param new_path Destination on the same filesystem and connection as `path`.
#' @inheritParams dir_ls
#' @return The destination path, invisibly.
#' @family filesystem operations
#' @export
file_copy <- function(path, new_path, con = NULL, ...) {
  if (is.null(con)) return(fs::file_copy(path, new_path, ...))
  .check_connection(con); .file_copy(con, .netfs_path_normalize(path), .netfs_path_normalize(new_path), ...)
}

#' Move a file within one filesystem
#' @inheritParams file_copy
#' @return The destination path, invisibly.
#' @family filesystem operations
#' @export
file_move <- function(path, new_path, con = NULL, ...) {
  if (is.null(con)) return(fs::file_move(path, new_path, ...))
  .check_connection(con); .file_move(con, .netfs_path_normalize(path), .netfs_path_normalize(new_path), ...)
}
