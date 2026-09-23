# Functions in this file are composed entirely from the existing internal
# generics (.dir_ls, .file_info, .file_exists, .dir_exists, .file_copy, ...)
# and their per-backend methods elsewhere. None of them need their own
# backend-specific code: they automatically work on every backend that
# supports their underlying primitives, and automatically fail with a clear
# "not supported by this backend" error where a primitive (e.g.
# .link_create/.link_path for anything but SSH) is itself unsupported.

.remote_walk <- function(con, path, type = "any", recurse = FALSE) {
  info <- .dir_info(con, path)
  if (!nrow(info)) return(info)
  if (!isTRUE(recurse)) {
    if (identical(type, "any")) return(info)
    return(info[as.character(info$type) %in% type, , drop = FALSE])
  }
  dirs <- as.character(info$path[!is.na(info$type) & as.character(info$type) == "directory"])
  nested <- lapply(dirs, function(d) .remote_walk(con, d, type = "any", recurse = TRUE))
  combined <- do.call(rbind, c(list(info), nested))
  if (identical(type, "any")) return(combined)
  combined[as.character(combined$type) %in% type, , drop = FALSE]
}

#' List directory contents recursively, with metadata
#' @inheritParams dir_ls
#' @param recurse Recurse fully into subdirectories?
#' @return Locally, the result of [fs::dir_info()]. Remotely, the same
#'   tibble shape as [file_info()], one row per entry.
#' @family filesystem operations
#' @export
dir_info <- function(path = ".", con = NULL, type = "any", recurse = FALSE, ...) {
  if (is.null(con)) return(fs::dir_info(path = path, type = type, recurse = recurse, ...))
  .check_connection(con)
  path <- .netfs_path_normalize(path)
  .remote_walk(con, path, type = type, recurse = recurse)
}

#' Apply a function to each entry in a directory
#' @inheritParams dir_ls
#' @param fun A function to apply to each path.
#' @param fail Passed to [fs::dir_map()] locally; remotely, always fails on
#'   a listing error (there is no partial-failure mode to suppress).
#' @return Locally, the result of [fs::dir_map()]. Remotely, a list of
#'   `fun`'s results, one per entry.
#' @family filesystem operations
#' @export
dir_map <- function(path = ".", con = NULL, fun, recurse = FALSE, type = "any", fail = TRUE) {
  if (is.null(con)) return(fs::dir_map(path, fun, recurse = recurse, type = type, fail = fail))
  .check_connection(con)
  lapply(dir_ls(path, con = con, type = type, recurse = recurse), fun)
}

#' Call a function on each entry in a directory, for its side effects
#' @inheritParams dir_map
#' @return `NULL`, invisibly.
#' @family filesystem operations
#' @export
dir_walk <- function(path = ".", con = NULL, fun, recurse = FALSE, type = "any", fail = TRUE) {
  if (is.null(con)) {
    fs::dir_walk(path, fun, recurse = recurse, type = type, fail = fail)
    return(invisible(NULL))
  }
  .check_connection(con)
  for (p in dir_ls(path, con = con, type = type, recurse = recurse)) fun(p)
  invisible(NULL)
}

#' Print directory contents in a tree-like format
#' @inheritParams dir_ls
#' @param recurse Recurse fully into subdirectories?
#' @return The root `path`, invisibly.
#' @family filesystem operations
#' @export
dir_tree <- function(path = ".", con = NULL, recurse = TRUE, ...) {
  if (is.null(con)) return(fs::dir_tree(path, recurse = recurse, ...))
  .check_connection(con)
  path <- .netfs_path_normalize(path)
  entries <- sort(as.character(.remote_walk(con, path, type = "any", recurse = recurse)$path))
  root_depth <- length(strsplit(sub("^/", "", path), "/", fixed = TRUE)[[1L]])
  cat(path, "\n", sep = "")
  for (p in entries) {
    depth <- length(strsplit(sub("^/", "", p), "/", fixed = TRUE)[[1L]]) - root_depth
    cat(strrep("  ", max(depth - 1L, 0L)), "\u2514\u2500\u2500 ", .remote_path_basename(p), "\n", sep = "")
  }
  invisible(fs::as_fs_path(path))
}

#' @rdname dir_ls
#' @export
file_size <- function(path, con = NULL) {
  if (is.null(con)) return(fs::file_size(path))
  file_info(path, con = con)$size
}

#' Test for file types
#' @inheritParams dir_ls
#' @return A logical vector.
#' @family filesystem operations
#' @export
is_file <- function(path, con = NULL) {
  if (is.null(con)) return(fs::is_file(path))
  file_exists(path, con = con)
}

#' @rdname is_file
#' @export
is_dir <- function(path, con = NULL) {
  if (is.null(con)) return(fs::is_dir(path))
  dir_exists(path, con = con)
}

#' @rdname is_file
#' @export
is_link <- function(path, con = NULL) {
  if (is.null(con)) return(fs::is_link(path))
  .check_connection(con)
  vapply(path, function(p) {
    info <- tryCatch(file_info(p, con = con), netfs_not_found = function(e) NULL)
    !is.null(info) && isTRUE(as.character(info$type) == "symlink")
  }, logical(1), USE.NAMES = FALSE)
}

#' @rdname is_file
#' @export
is_file_empty <- function(path, con = NULL) {
  if (is.null(con)) return(fs::is_file_empty(path))
  .check_connection(con)
  vapply(path, function(p) {
    info <- tryCatch(file_info(p, con = con), netfs_not_found = function(e) NULL)
    !is.null(info) && isTRUE(as.numeric(info$size) == 0)
  }, logical(1), USE.NAMES = FALSE)
}

#' Check if a directory is empty
#' @inheritParams dir_ls
#' @return A logical vector.
#' @family filesystem operations
#' @export
is_dir_empty <- function(path, con = NULL) {
  if (is.null(con)) return(fs::is_dir_empty(path))
  .check_connection(con)
  vapply(path, function(p) length(dir_ls(p, con = con)) == 0L, logical(1), USE.NAMES = FALSE)
}

#' Query for existence and access permissions
#'
#' Remotely, `mode = "exists"` (the default) works on every backend. The
#' `"read"`/`"write"`/`"execute"` modes require a permission-bit query the
#' connection can actually make; currently only SSH can (`test -r`/`-w`/`-x`
#' on the remote shell).
#' @inheritParams dir_ls
#' @param mode One or more of `"exists"`, `"read"`, `"write"`, `"execute"`.
#' @return A logical vector.
#' @family filesystem operations
#' @export
file_access <- function(path, con = NULL, mode = "exists") {
  if (is.null(con)) return(fs::file_access(path, mode = mode))
  .check_connection(con)
  known <- c("exists", "read", "write", "execute")
  if (!all(mode %in% known)) {
    rlang::abort('`mode` must be one or more of "exists", "read", "write", "execute".', class = "netfs_validation_error")
  }
  vapply(path, function(p) {
    p <- .netfs_path_normalize(p)
    ok <- TRUE
    if ("exists" %in% mode) ok <- .file_exists(con, p) || .dir_exists(con, p)
    other <- setdiff(mode, "exists")
    if (ok && length(other)) ok <- .file_access(con, p, other)
    isTRUE(ok)
  }, logical(1), USE.NAMES = FALSE)
}

#' Change file permissions
#' @inheritParams dir_ls
#' @param mode A permission string accepted by [fs::as_fs_perms()] (e.g.
#'   `"644"` or `"u=rw,go=r"`).
#' @return The path, invisibly, as an `fs_path`.
#' @family filesystem operations
#' @export
file_chmod <- function(path, con = NULL, mode) {
  if (is.null(con)) return(fs::file_chmod(path, mode))
  .check_connection(con)
  invisible(fs::as_fs_path(vapply(path, function(p) {
    as.character(.file_chmod(con, .netfs_path_normalize(p), mode))
  }, character(1), USE.NAMES = FALSE)))
}

#' Change owner or group of a file
#' @inheritParams dir_ls
#' @param user_id,group_id Numeric user/group id. At least one is required.
#' @return The path, invisibly, as an `fs_path`.
#' @family filesystem operations
#' @export
file_chown <- function(path, con = NULL, user_id = NULL, group_id = NULL) {
  if (is.null(con)) return(fs::file_chown(path, user_id = user_id, group_id = group_id))
  .check_connection(con)
  invisible(fs::as_fs_path(vapply(path, function(p) {
    as.character(.file_chown(con, .netfs_path_normalize(p), user_id, group_id))
  }, character(1), USE.NAMES = FALSE)))
}

#' Change file access and modification times
#' @inheritParams dir_ls
#' @param access_time,modification_time Timestamps to set. Defaulting both
#'   to "now" uses a plain, universally portable `touch`; an explicit,
#'   different timestamp requires GNU `touch` on the remote.
#' @return The path, invisibly, as an `fs_path`.
#' @family filesystem operations
#' @export
file_touch <- function(path, con = NULL, access_time = Sys.time(), modification_time = access_time) {
  if (is.null(con)) return(fs::file_touch(path, access_time = access_time, modification_time = modification_time))
  .check_connection(con)
  invisible(fs::as_fs_path(vapply(path, function(p) {
    as.character(.file_touch(con, .netfs_path_normalize(p), access_time, modification_time))
  }, character(1), USE.NAMES = FALSE)))
}

#' Create a file
#'
#' Remotely, an existing file is left untouched (its content is never
#' truncated), matching [fs::file_create()]'s local behavior; a missing one
#' is created empty via an upload. Unlike the local version, an existing
#' remote file's modification time is not bumped.
#' @inheritParams dir_ls
#' @return The path, invisibly, as an `fs_path`.
#' @family filesystem operations
#' @export
file_create <- function(path, con = NULL, ...) {
  if (is.null(con)) return(fs::file_create(path, ...))
  .check_connection(con)
  invisible(fs::as_fs_path(vapply(path, function(p) {
    p <- .netfs_path_normalize(p)
    if (.file_exists(con, p)) return(p)
    tmp <- tempfile("netfs-create-")
    on.exit(if (fs::file_exists(tmp)) fs::file_delete(tmp), add = TRUE)
    fs::file_create(tmp)
    as.character(.file_upload(con, tmp, p))
  }, character(1), USE.NAMES = FALSE)))
}

#' Open a file or directory
#'
#' Not supported for remote connections: this opens a path in a local
#' viewer application, and a remote path isn't on this machine. Call
#' [file_download()] first, then [fs::file_show()] on the local copy.
#' @inheritParams dir_ls
#' @param browser Passed to [fs::file_show()] locally.
#' @return Locally, the result of [fs::file_show()].
#' @family filesystem operations
#' @export
file_show <- function(path, con = NULL, browser = getOption("browser")) {
  if (is.null(con)) return(fs::file_show(path, browser = browser))
  .check_connection(con)
  abort_netfs_unsupported(
    "file_show() is not supported for remote connections: it opens a path in a local viewer, and a remote path isn't on this machine. Use file_download() first, then fs::file_show() on the local copy.",
    operation = "file_show"
  )
}

.copy_via_staging <- function(con, path, new_path) {
  tmp <- tempfile("netfs-dircopy-")
  on.exit(if (fs::file_exists(tmp)) fs::file_delete(tmp), add = TRUE)
  .file_download(con, path, tmp)
  .file_upload(con, tmp, new_path)
}

#' Copy a directory
#'
#' On a backend without server-side [file_copy()] (currently FTP), each
#' file is instead copied through a local staging file - one download
#' followed by one upload - so the copy still completes; it's just slower
#' than SSH's `cp` or SMB's native server-side copy.
#' @inheritParams file_copy
#' @param overwrite Replace an existing destination directory.
#' @return The destination path, invisibly, as an `fs_path`.
#' @family filesystem operations
#' @export
dir_copy <- function(path, new_path, con = NULL, overwrite = FALSE) {
  if (is.null(con)) return(fs::dir_copy(path, new_path, overwrite = overwrite))
  .check_connection(con)
  path <- .netfs_path_normalize(path); new_path <- .netfs_path_normalize(new_path)
  if (!.dir_exists(con, path)) abort_netfs_not_found(sprintf("Remote directory `%s` was not found.", path))
  if (!overwrite && .dir_exists(con, new_path)) {
    abort_netfs(sprintf("Remote destination `%s` already exists; set `overwrite = TRUE` to replace it.", new_path), "netfs_destination_exists")
  }
  .dir_create(con, new_path)
  entries <- .remote_walk(con, path, type = "any", recurse = TRUE)
  for (i in seq_len(nrow(entries))) {
    entry_path <- as.character(entries$path[[i]])
    relative <- substring(entry_path, nchar(path) + 1L)
    destination <- .remote_path_join(new_path, relative)
    if (identical(as.character(entries$type[[i]]), "directory")) {
      .dir_create(con, destination)
    } else {
      tryCatch(
        .file_copy(con, entry_path, destination),
        netfs_unsupported = function(e) .copy_via_staging(con, entry_path, destination)
      )
    }
  }
  invisible(fs::as_fs_path(new_path))
}

#' Create a symbolic (or hard) link
#' @param path Target the link points to.
#' @param new_path Location of the new link.
#' @param symbolic Create a symbolic link (`TRUE`, the default) or a hard link.
#' @inheritParams dir_ls
#' @return `new_path`, invisibly, as an `fs_path`.
#' @family filesystem operations
#' @export
link_create <- function(path, new_path, con = NULL, symbolic = TRUE) {
  if (is.null(con)) return(fs::link_create(path, new_path, symbolic = symbolic))
  .check_connection(con)
  invisible(fs::as_fs_path(as.character(
    .link_create(con, .netfs_path_normalize(path), .netfs_path_normalize(new_path), symbolic)
  )))
}

#' Read the target of a symbolic link
#' @inheritParams dir_ls
#' @return An `fs_path` vector of link targets.
#' @family filesystem operations
#' @export
link_path <- function(path, con = NULL) {
  if (is.null(con)) return(fs::link_path(path))
  .check_connection(con)
  fs::as_fs_path(vapply(path, function(p) as.character(.link_path(con, .netfs_path_normalize(p))), character(1), USE.NAMES = FALSE))
}

#' Delete a symbolic link
#' @inheritParams dir_ls
#' @return The path, invisibly, as an `fs_path`.
#' @family filesystem operations
#' @export
link_delete <- function(path, con = NULL) {
  if (is.null(con)) return(fs::link_delete(path))
  .check_connection(con)
  invisible(fs::as_fs_path(vapply(path, function(p) as.character(.link_delete(con, .netfs_path_normalize(p))), character(1), USE.NAMES = FALSE)))
}

#' Copy a symbolic link
#' @inheritParams file_copy
#' @param overwrite Replace an existing destination.
#' @return The destination path, invisibly, as an `fs_path`.
#' @family filesystem operations
#' @export
link_copy <- function(path, new_path, con = NULL, overwrite = FALSE) {
  if (is.null(con)) return(fs::link_copy(path, new_path, overwrite = overwrite))
  .check_connection(con)
  path <- .netfs_path_normalize(path); new_path <- .netfs_path_normalize(new_path)
  if (!overwrite && (.file_exists(con, new_path) || .dir_exists(con, new_path))) {
    abort_netfs(sprintf("Remote destination `%s` already exists; set `overwrite = TRUE` to replace it.", new_path), "netfs_destination_exists")
  }
  if (overwrite) tryCatch(.file_delete(con, new_path), netfs_not_found = function(e) NULL)
  target <- as.character(.link_path(con, path))
  invisible(fs::as_fs_path(as.character(.link_create(con, target, new_path, TRUE))))
}
