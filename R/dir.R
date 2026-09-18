#' List directory contents
#' @param path A local or remote path. For `dir_ls()`, a connection supplied as
#'   the first argument is shorthand for listing that connection's root.
#' @param con `NULL` for local `fs` behavior, or a netfs connection.
#' @param ... Arguments passed to `fs::dir_ls()` locally or to the backend.
#' @return A path vector. Remote paths use forward slashes.
#' @family filesystem operations
#' @seealso [fs::dir_ls()]
#' @examples
#' dir_ls(tempdir())
#' @export
dir_ls <- function(path = ".", con = NULL, ...) {
  if (is_netfs_connection(path)) {
    if (!is.null(con)) {
      rlang::abort(
        "When `path` is a connection, `con` must be omitted.",
        class = "netfs_validation_error"
      )
    }
    con <- path
    path <- "/"
  }
  if (is.null(con)) return(fs::dir_ls(path = path, ...))
  .check_connection(con); .dir_ls(con, .netfs_path_normalize(path), ...)
}

#' Test whether directories exist
#' @inheritParams dir_ls
#' @return A logical vector.
#' @family filesystem operations
#' @export
dir_exists <- function(path, con = NULL) {
  if (is.null(con)) return(fs::dir_exists(path))
  .check_connection(con); vapply(path, function(x) .dir_exists(con, .netfs_path_normalize(x)), logical(1))
}

#' Create a directory
#' @inheritParams dir_ls
#' @return The path, invisibly. Remote creation is non-recursive unless explicitly supported by a backend argument.
#' @family filesystem operations
#' @export
dir_create <- function(path, con = NULL, ...) {
  if (is.null(con)) return(fs::dir_create(path, ...))
  .check_connection(con); .dir_create(con, .netfs_path_normalize(path), ...)
}

#' Delete a directory
#' @inheritParams dir_ls
#' @return The path, invisibly. Remote deletion does not recursively delete contents.
#' @family filesystem operations
#' @export
dir_delete <- function(path, con = NULL, ...) {
  if (is.null(con)) return(fs::dir_delete(path, ...))
  .check_connection(con); .dir_delete(con, .netfs_path_normalize(path), ...)
}
