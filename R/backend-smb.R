.smb_service <- function(con) paste0("//", con$host, "/", con$share)
.smb_path <- function(path) gsub("/", "\\\\", sub("^/", "", .netfs_path_normalize(path)), fixed = TRUE)

.smb_common_args <- function(con) {
  args <- c(.smb_service(con), "-g")
  if (!is.null(con$user)) args <- c(args, "-U", paste0(if (is.null(con$domain)) "" else paste0(con$domain, "\\"), con$user)) else args <- c(args, "-N")
  args
}

.require_smbclient <- function() {
  if (.has_smbclient()) return(invisible(TRUE))

  message <- paste0(
    "SMB operations require the Samba smbclient utility. Install your ",
    "distribution's smbclient or samba-client package first. A Samba server ",
    "is needed only when this machine will host shares. See ",
    "https://www.samba.org/samba/docs/current/man-html/smbclient.1.html."
  )
  abort_netfs_backend_unavailable(message, command = "smbclient")
}

.is_macos <- function() identical(tolower(Sys.info()[["sysname"]]), "darwin")
.is_windows <- function() identical(.Platform$OS.type, "windows")
.smb_uses_native_fs <- function() .is_windows() || .is_macos()

.applescript_string <- function(x) {
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub('"', '\\"', x, fixed = TRUE)
  paste0('"', x, '"')
}

.smb_macos_mount <- function(con) {
  .check_connection(con)
  password <- .connection_password(con)
  username <- con$user
  if (!is.null(username) && !is.null(con$domain)) {
    username <- paste0(con$domain, "\\", username)
  }
  service <- paste0(
    "smb://",
    utils::URLencode(con$host, reserved = TRUE),
    "/",
    utils::URLencode(con$share, reserved = TRUE)
  )

  command <- paste0("set mountedVolume to mount volume ", .applescript_string(service))
  if (!is.null(username)) {
    command <- paste0(command, " as user name ", .applescript_string(username))
  }
  if (!is.null(password)) {
    command <- paste0(command, " with password ", .applescript_string(password))
  }
  script <- paste(command, "return POSIX path of mountedVolume", sep = "\n")
  result <- .run_command(
    "/usr/bin/osascript",
    args = "-",
    stdin = script,
    timeout = 60,
    redact = password %||% ""
  )
  if (result$status != 0L) {
    detail <- paste(result$stderr, result$stdout)
    if (grepl("auth|password|permission", detail, ignore.case = TRUE)) {
      abort_netfs_auth(
        sprintf("SMB authentication to `%s` failed.", con$host),
        result = result
      )
    }
    abort_netfs_connection(
      sprintf("macOS could not mount SMB share `%s/%s`.", con$host, con$share),
      result = result
    )
  }
  mount_path <- trimws(result$stdout)
  if (!nzchar(mount_path)) {
    abort_netfs_connection(
      sprintf("macOS mounted SMB share `%s/%s` without returning its path.", con$host, con$share),
      result = result
    )
  }
  mount_path
}

.smb_native_path <- function(con, path) {
  if (.is_windows()) return(.smb_to_unc(con, path))
  root <- .smb_macos_mount(con)
  relative <- sub("^/", "", .netfs_path_normalize(path))
  if (!nzchar(relative)) return(root)
  parts <- strsplit(relative, "/", fixed = TRUE)[[1L]]
  do.call(fs::path, as.list(c(root, parts)))
}

.smb_run <- function(con, command) {
  .require_smbclient()
  password <- .connection_password(con)
  secrets <- c(password %||% "")
  env <- if (is.null(password)) NULL else c(PASSWD = password)
  result <- .run_command("smbclient", c(.smb_common_args(con), "-c", command), env = env, redact = secrets)
  if (result$status == 0L) return(result)
  detail <- paste(result$stderr, result$stdout)
  if (grepl("LOGON_FAILURE|ACCESS_DENIED", detail)) abort_netfs_auth(sprintf("SMB authentication to `%s` failed.", con$host), result = result)
  if (grepl("OBJECT_NAME_NOT_FOUND|NO_SUCH_FILE", detail)) abort_netfs_not_found(sprintf("SMB path was not found on `%s`.", con$host), result = result)
  abort_netfs_connection(sprintf("SMB operation on `%s` failed.", con$host), result = result)
}

.smb_parse_listing <- function(text, base = "/") {
  lines <- strsplit(text, "\r?\n")[[1L]]
  fields <- strsplit(lines[nzchar(lines)], "|", fixed = TRUE)
  fields <- fields[vapply(fields, length, integer(1)) >= 4L]
  if (!length(fields)) return(.new_remote_info(character()))
  name <- vapply(fields, `[[`, character(1), 2L)
  keep <- !name %in% c(".", "..")
  fields <- fields[keep]; name <- name[keep]
  type <- vapply(fields, function(x) if (grepl("D", x[[1L]], fixed = TRUE)) "directory" else "file", character(1))
  size <- suppressWarnings(as.numeric(vapply(fields, `[[`, character(1), 3L)))
  .new_remote_info(unname(vapply(name, function(x) .remote_path_join(base, x), character(1))), type, size)
}

.dir_ls.netfs_smb <- function(con, path, ...) {
  if (.smb_uses_native_fs()) {
    root <- .smb_native_path(con, path)
    names <- fs::dir_ls(root, ...)
    return(vapply(basename(names), function(x) .remote_path_join(path, x), character(1)))
  }
  info <- .smb_parse_listing(.smb_run(con, sprintf("ls %s", shQuote(.smb_path(path), type = "cmd")))$stdout, path)
  info$path
}
.file_exists.netfs_smb <- function(con, path, ...) {
  if (.smb_uses_native_fs()) return(fs::file_exists(.smb_native_path(con, path)))
  tryCatch({ .smb_run(con, sprintf("allinfo %s", shQuote(.smb_path(path), type = "cmd"))); TRUE }, netfs_not_found = function(e) FALSE)
}
.dir_exists.netfs_smb <- function(con, path, ...) {
  if (.smb_uses_native_fs()) return(fs::dir_exists(.smb_native_path(con, path)))
  tryCatch({ .smb_run(con, sprintf("cd %s", shQuote(.smb_path(path), type = "cmd"))); TRUE }, netfs_not_found = function(e) FALSE)
}
.file_info.netfs_smb <- function(con, path, ...) {
  if (.smb_uses_native_fs()) {
    x <- fs::file_info(.smb_native_path(con, path))
    return(.new_remote_info(path, as.character(x$type), x$size, x$modification_time))
  }
  if (!.file_exists.netfs_smb(con, path) && !.dir_exists.netfs_smb(con, path)) abort_netfs_not_found(sprintf("SMB path `%s` was not found.", path))
  .new_remote_info(path, if (.dir_exists.netfs_smb(con, path)) "directory" else "file")
}

.smb_native_mutate <- function(fun, con, path, new_path = NULL, ...) {
  out <- if (is.null(new_path)) fun(.smb_native_path(con, path), ...) else fun(.smb_native_path(con, path), .smb_native_path(con, new_path), ...)
  invisible(new_path %||% path)
}
.dir_create.netfs_smb <- function(con, path, ...) if (.smb_uses_native_fs()) .smb_native_mutate(fs::dir_create, con, path, ...) else { .smb_run(con, sprintf("mkdir %s", shQuote(.smb_path(path), type = "cmd"))); invisible(path) }
.dir_delete.netfs_smb <- function(con, path, ...) if (.smb_uses_native_fs()) .smb_native_mutate(fs::dir_delete, con, path, ...) else { .smb_run(con, sprintf("rmdir %s", shQuote(.smb_path(path), type = "cmd"))); invisible(path) }
.file_delete.netfs_smb <- function(con, path, ...) if (.smb_uses_native_fs()) .smb_native_mutate(fs::file_delete, con, path, ...) else { .smb_run(con, sprintf("del %s", shQuote(.smb_path(path), type = "cmd"))); invisible(path) }
.file_move.netfs_smb <- function(con, path, new_path, ...) if (.smb_uses_native_fs()) .smb_native_mutate(fs::file_move, con, path, new_path, ...) else { .smb_run(con, sprintf("rename %s %s", shQuote(.smb_path(path), type = "cmd"), shQuote(.smb_path(new_path), type = "cmd"))); invisible(new_path) }
.file_copy.netfs_smb <- function(con, path, new_path, ...) if (.smb_uses_native_fs()) .smb_native_mutate(fs::file_copy, con, path, new_path, ...) else abort_netfs_unsupported("Server-side file copy is not supported by the smbclient backend.")

.file_download.netfs_smb <- function(con, path, local, ...) {
  if (.smb_uses_native_fs()) { fs::file_copy(.smb_native_path(con, path), local, overwrite = TRUE); return(invisible(local)) }
  .smb_run(con, sprintf("get %s %s", shQuote(.smb_path(path), type = "cmd"), shQuote(fs::path_abs(local), type = "cmd"))); invisible(local)
}
.file_upload.netfs_smb <- function(con, local, path, ...) {
  if (.smb_uses_native_fs()) { fs::file_copy(local, .smb_native_path(con, path), overwrite = TRUE); return(invisible(path)) }
  .smb_run(con, sprintf("put %s %s", shQuote(fs::path_abs(local), type = "cmd"), shQuote(.smb_path(path), type = "cmd"))); invisible(path)
}
