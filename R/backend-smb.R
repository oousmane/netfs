.smb_service <- function(con) paste0("//", con$host, "/", con$share)
.smb_path <- function(path) gsub("/", "\\", sub("^/", "", .netfs_path_normalize(path)), fixed = TRUE)

.smb_common_args <- function(con) {
  # smbclient's -g/--grepable does not change `ls`/`dir` output on macOS/Linux
  # builds (verified against 4.24.x); .smb_listing_pattern parses the
  # standard columnar format instead.
  # smbclient's default send-buffer is small enough that a slow or lossy
  # connection can stall long enough to trip the server's own I/O timeout
  # mid-transfer (observed as NT_STATUS_IO_TIMEOUT on a 36MB upload over a
  # ~550kB/s link). A larger buffer avoids that; override via
  # `smb(..., send_buffer = <bytes>)` if a specific value is needed.
  send_buffer <- if (is.null(con$options$send_buffer)) 130048L else con$options$send_buffer
  args <- c(.smb_service(con), "-b", as.character(send_buffer))
  if (!is.null(con$user)) args <- c(args, "-U", paste0(if (is.null(con$domain)) "" else paste0(con$domain, "\\"), con$user)) else args <- c(args, "-N")
  args
}

.require_smbclient <- function() {
  if (.has_smbclient()) return(invisible(TRUE))

  message <- if (.is_macos()) {
    paste0(
      "SMB operations require the Samba smbclient utility. Install it with ",
      "Homebrew (`brew install samba`) first; the MacPorts `samba4` port is ",
      "known to crash on connect on some macOS versions. A Samba server is ",
      "needed only when this machine will host shares. See ",
      "https://www.samba.org/samba/docs/current/man-html/smbclient.1.html."
    )
  } else {
    paste0(
      "SMB operations require the Samba smbclient utility. Install your ",
      "distribution's smbclient or samba-client package first. A Samba server ",
      "is needed only when this machine will host shares. See ",
      "https://www.samba.org/samba/docs/current/man-html/smbclient.1.html."
    )
  }
  abort_netfs_backend_unavailable(message, command = "smbclient")
}

.is_macos <- function() identical(tolower(Sys.info()[["sysname"]]), "darwin")
.is_windows <- function() identical(.Platform$OS.type, "windows")
.smb_uses_native_fs <- function() .is_windows()

.smb_native_path <- function(con, path) .smb_to_unc(con, path)

.smb_run <- function(con, command) {
  .require_smbclient()
  password <- .connection_password(con)
  secrets <- c(password %||% "")
  env <- if (is.null(password)) NULL else c("current", PASSWD = password)
  result <- .run_command("smbclient", c(.smb_common_args(con), "-c", command), env = env, redact = secrets)
  if (result$status == 0L) return(result)
  detail <- paste(result$stderr, result$stdout)
  if (grepl("LOGON_FAILURE|ACCESS_DENIED", detail)) abort_netfs_auth(sprintf("SMB authentication to `%s` failed.", con$host), result = result)
  if (grepl("OBJECT_NAME_NOT_FOUND|NO_SUCH_FILE|NOT_A_DIRECTORY", detail)) abort_netfs_not_found(sprintf("SMB path was not found on `%s`.", con$host), result = result)
  detail <- trimws(detail)
  message <- if (nzchar(detail)) {
    sprintf("SMB operation on `%s` failed: %s", con$host, detail)
  } else {
    sprintf("SMB operation on `%s` failed.", con$host)
  }
  abort_netfs_connection(message, result = result)
}

.smb_listing_pattern <- "^\\s*(.*?\\S)\\s{2,}([A-Za-z]*)\\s+(-?\\d+)\\s+(\\S.*)$"

.smb_parse_listing <- function(text, base = "/") {
  lines <- strsplit(text, "\r?\n")[[1L]]
  fields <- regmatches(lines, regexec(.smb_listing_pattern, lines, perl = TRUE))
  fields <- fields[vapply(fields, length, integer(1)) == 5L]
  if (!length(fields)) return(.new_remote_info(character()))
  name <- vapply(fields, `[[`, character(1), 2L)
  keep <- !name %in% c(".", "..")
  fields <- fields[keep]; name <- name[keep]
  if (!length(fields)) return(.new_remote_info(character()))
  attrs <- vapply(fields, `[[`, character(1), 3L)
  type <- ifelse(grepl("D", attrs, fixed = TRUE), "directory", "file")
  size <- suppressWarnings(as.numeric(vapply(fields, `[[`, character(1), 4L)))
  .new_remote_info(unname(vapply(name, function(x) .remote_path_join(base, x), character(1))), type, size)
}

.dir_info.netfs_smb <- function(con, path, ...) {
  if (.smb_uses_native_fs()) {
    root <- .smb_native_path(con, path)
    x <- fs::dir_info(root, ...)
    remote_path <- unname(vapply(basename(as.character(x$path)), function(n) .remote_path_join(path, n), character(1)))
    return(.new_remote_info(remote_path, as.character(x$type), as.numeric(x$size), x$modification_time))
  }
  target <- .smb_path(path)
  # smbclient's `ls <name>` treats <name> as a mask against the current
  # directory's entries, not a directory to enter — without a trailing
  # wildcard it matches only the directory's own entry, not its contents.
  command <- if (nzchar(target)) sprintf("ls %s", shQuote(paste0(target, "\\*"), type = "cmd")) else "ls"
  .smb_parse_listing(.smb_run(con, command)$stdout, path)
}
.dir_ls.netfs_smb <- function(con, path, ...) as.character(.dir_info.netfs_smb(con, path, ...)$path)
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
