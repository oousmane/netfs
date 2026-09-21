.netfs_path_normalize <- function(path) {
  .check_scalar_character(path, "path", allow_empty = TRUE)
  path <- gsub("\\\\", "/", path)
  path <- gsub("/+", "/", path)
  if (!nzchar(path) || path == ".") return("/")
  path <- paste0("/", sub("^/+", "", path))
  if (nchar(path) > 1L) path <- sub("/+$", "", path)
  parts <- strsplit(sub("^/", "", path), "/", fixed = TRUE)[[1L]]
  if (any(parts == "..")) abort_netfs("Remote paths cannot contain `..`.", class = "netfs_validation_error")
  paste0("/", paste(parts[parts != "." & nzchar(parts)], collapse = "/"))
}

.remote_path_join <- function(...) {
  parts <- list(...)
  .netfs_path_normalize(paste(unlist(parts, use.names = FALSE), collapse = "/"))
}

.remote_path_basename <- function(path) {
  path <- .netfs_path_normalize(path)
  if (path == "/") return("")
  sub(".*/", "", path)
}

.remote_path_dirname <- function(path) {
  path <- .netfs_path_normalize(path)
  if (path == "/" || !grepl("/", sub("^/", "", path), fixed = TRUE)) return("/")
  sub("/[^/]+$", "", path)
}

.has_trailing_path_separator <- function(path) {
  grepl("[/\\\\]$", path)
}

.is_local_dir <- function(path) {
  isTRUE(fs::dir_exists(path))
}

.is_remote_dir <- function(path, con) {
  .check_connection(con)
  isTRUE(.dir_exists(con, .netfs_path_normalize(path)))
}

.is_dir <- function(path, con = NULL) {
  .check_scalar_character(path, "path")
  if (is.null(con)) return(.is_local_dir(path))
  .is_remote_dir(path, con)
}

.next_available_local_path <- function(path) {
  if (!fs::file_exists(path) && !fs::dir_exists(path)) return(path)

  extension <- tools::file_ext(path)
  stem <- tools::file_path_sans_ext(path)
  suffix <- if (nzchar(extension)) paste0(".", extension) else ""
  index <- 1L
  repeat {
    candidate <- paste0(stem, "-", index, suffix)
    if (!fs::file_exists(candidate) && !fs::dir_exists(candidate)) {
      return(candidate)
    }
    index <- index + 1L
  }
}
