#' Download a remote file
#' @param path Remote source path.
#' @param local Local destination path. If this is an existing directory or
#'   ends in a path separator, the basename of `path` is appended.
#' @param con A remote connection.
#' @param overwrite Replace an existing destination. For downloads, `FALSE`
#'   preserves an existing file and selects a numbered name such as
#'   `report-1.csv`.
#' @param ... Backend arguments.
#' @return The absolute local destination, invisibly.
#' @family filesystem operations
#' @examples
#' \dontrun{
#' con <- smb("fileserver", "DATA", user = "alice")
#' file_download(
#'   path = "/DEMANDES_DONNEES/nakoulma.xls",
#'   local = "C:/Users/alice/Downloads/nakoulma.xls",
#'   con = con
#' )
#' }
#' @export
file_download <- function(path, local = basename(path), con, overwrite = FALSE, ...) {
  if (missing(con)) {
    rlang::abort(
      "`con` is required for remote file downloads.",
      class = "netfs_validation_error"
    )
  }
  .check_connection(con); .check_scalar_logical(overwrite, "overwrite")
  .check_scalar_character(path, "path")
  .check_scalar_character(local, "local")
  path <- .netfs_path_normalize(path)
  if (.has_trailing_path_separator(local) || .is_dir(local)) {
    filename <- .remote_path_basename(path)
    if (!nzchar(filename)) {
      rlang::abort(
        "`path` must identify a file when `local` is a directory.",
        class = "netfs_validation_error"
      )
    }
    local <- fs::path(local, filename)
  }
  if (!overwrite) local <- .next_available_local_path(local)
  .file_download(con, path, local, ...)
  invisible(fs::path_abs(local))
}

#' Upload a local file
#' @param local Local source path.
#' @param path Remote destination path. If it identifies an existing directory
#'   or ends in `/`, the basename of `local` is appended.
#' @param overwrite Replace an existing remote destination. When `FALSE`, an
#'   existing destination raises `netfs_destination_exists`.
#' @inheritParams file_download
#' @return The normalized remote destination, invisibly.
#' @family filesystem operations
#' @examples
#' \dontrun{
#' con <- smb("fileserver", "DATA", user = "alice")
#' file_upload(
#'   local = "C:/Users/alice/Documents/BAD26011.pdf",
#'   path = "/BAD-netfs/",
#'   con = con
#' )
#' }
#' @export
file_upload <- function(local, path, con, overwrite = FALSE, ...) {
  if (missing(con)) {
    rlang::abort(
      "`con` is required for remote file uploads.",
      class = "netfs_validation_error"
    )
  }
  .check_connection(con); .check_scalar_logical(overwrite, "overwrite")
  .check_scalar_character(local, "local")
  .check_scalar_character(path, "path")
  if (!fs::file_exists(local)) abort_netfs_not_found(sprintf("Local source `%s` does not exist.", local), path = local)
  remote_directory <- .has_trailing_path_separator(path) || .is_dir(path, con)
  path <- .netfs_path_normalize(path)
  if (remote_directory) path <- .remote_path_join(path, fs::path_file(local))
  if (!overwrite && .file_exists(con, path)) {
    abort_netfs(
      sprintf(
        "Remote destination `%s` already exists; set `overwrite = TRUE` to replace it.",
        path
      ),
      "netfs_destination_exists"
    )
  }
  .file_upload(con, local, path, ...)
  invisible(path)
}

#' Transfer a file between remote connections
#'
#' `file_transfer()` moves data through a temporary local file. It does not
#' request a direct server-to-server transfer. The temporary file is removed
#' whether the transfer succeeds or fails. The source is never deleted.
#'
#' @param path Source path inside `from`.
#' @param new_path Destination path inside `to`. If it identifies an existing
#'   directory or ends in `/`, the basename of `path` is appended.
#' @param from Source connection.
#' @param to Destination connection.
#' @param overwrite Replace an existing destination file.
#' @return The normalized remote destination path, invisibly.
#' @family filesystem operations
#' @examples
#' \dontrun{
#' ftp_server <- ftp("ftp.example.org", user = "analyst")
#' smb_server <- smb("fileserver", "DATA", user = "analyst")
#'
#' file_transfer(
#'   path = "/incoming/report.csv",
#'   new_path = "/archive/",
#'   from = ftp_server,
#'   to = smb_server
#' )
#' }
#' @export
file_transfer <- function(path, new_path = basename(path), from, to,
                          overwrite = FALSE) {
  .check_connection(from)
  .check_connection(to)
  .check_scalar_character(path, "path")
  .check_scalar_character(new_path, "new_path")
  .check_scalar_logical(overwrite, "overwrite")

  path <- .netfs_path_normalize(path)
  destination_is_dir <- .has_trailing_path_separator(new_path) ||
    .is_dir(new_path, to)
  new_path <- .netfs_path_normalize(new_path)
  if (destination_is_dir) {
    filename <- .remote_path_basename(path)
    if (!nzchar(filename)) {
      rlang::abort(
        "`path` must identify a file when `new_path` is a directory.",
        class = "netfs_validation_error"
      )
    }
    new_path <- .remote_path_join(new_path, filename)
  }

  staging_file <- tempfile("netfs-transfer-")
  on.exit({
    if (fs::file_exists(staging_file)) fs::file_delete(staging_file)
  }, add = TRUE)

  file_download(path, local = staging_file, con = from, overwrite = TRUE)
  file_upload(
    local = staging_file,
    path = new_path,
    con = to,
    overwrite = overwrite
  )
  invisible(new_path)
}
