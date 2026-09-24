#' List directory contents
#' @param path A local or remote path. For `dir_ls()`, a connection supplied as
#'   the first argument is shorthand for listing that connection's root.
#' @param con `NULL` for local `fs` behavior, or a netfs connection.
#' @param type One or more of [fs::file_info()]'s type levels (e.g.
#'   `"file"`, `"directory"`) to filter the listing to; `"any"` (the
#'   default) returns everything. An entry whose type can't be determined
#'   never matches a specific type. Filtering by type, like `recurse`,
#'   costs one extra request per entry on backends that don't return type
#'   with the listing itself.
#' @param recurse Recurse fully into subdirectories?
#' @param ... Arguments passed to `fs::dir_ls()` locally or to the backend.
#' @return An `fs_path` vector. Remote paths use forward slashes.
#' @family filesystem operations
#' @seealso [fs::dir_ls()]
#' @examples
#' dir_ls(tempdir())
#' @export
dir_ls <- function(path = ".", con = NULL, type = "any", recurse = FALSE, ...) {
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
  if (is.null(con)) return(fs::dir_ls(path = path, type = type, recurse = recurse, ...))
  .check_connection(con)
  path <- .netfs_path_normalize(path)
  if (!isTRUE(recurse) && identical(type, "any")) return(fs::as_fs_path(unname(.dir_ls(con, path, ...))))
  info <- .remote_walk(con, path, type = type, recurse = recurse)
  fs::as_fs_path(unname(as.character(info$path)))
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
#' @return The path, invisibly, as an `fs_path`. Remote creation is
#'   non-recursive unless the backend offers its own way to opt in.
#' @family filesystem operations
#' @export
dir_create <- function(path, con = NULL, ...) {
  if (is.null(con)) return(fs::dir_create(path, ...))
  .check_connection(con)
  invisible(fs::as_fs_path(.dir_create(con, .netfs_path_normalize(path), ...)))
}

#' Delete a directory
#' @inheritParams dir_ls
#' @param recurse Delete the directory's contents first if it isn't empty.
#'   `FALSE` (the default) fails instead, unlike local [fs::dir_delete()],
#'   which is always recursive. SMB deletes recursively regardless of this
#'   argument, since its native delete already works that way.
#' @return The path, invisibly, as an `fs_path`.
#' @family filesystem operations
#' @export
dir_delete <- function(path, con = NULL, recurse = FALSE, ...) {
  if (is.null(con)) return(fs::dir_delete(path, ...))
  .check_connection(con); .check_scalar_logical(recurse, "recurse")
  path <- .netfs_path_normalize(path)
  if (isTRUE(recurse)) {
    entries <- .remote_walk(con, path, type = "any", recurse = TRUE)
    if (nrow(entries)) {
      paths <- as.character(entries$path)
      # Deepest entries first, so a directory is always empty by the time
      # its own turn comes - both a file and a subdirectory a level deeper
      # than their parent qualify equally here, only depth matters.
      depth <- lengths(strsplit(paths, "/", fixed = TRUE))
      for (i in order(-depth)) {
        if (identical(as.character(entries$type[[i]]), "directory")) .dir_delete(con, paths[[i]]) else .file_delete(con, paths[[i]])
      }
    }
  }
  invisible(fs::as_fs_path(.dir_delete(con, path, ...)))
}
