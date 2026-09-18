.ssh_target <- function(con) if (is.null(con$user)) con$host else paste0(con$user, "@", con$host)

.ssh_common_args <- function(con) {
  args <- c("-p", as.character(con$port), "-o", "BatchMode=yes")
  if (!is.null(con$identity_file)) args <- c(args, "-i", con$identity_file)
  args
}

.scp_common_args <- function(con) {
  args <- c("-P", as.character(con$port), "-o", "BatchMode=yes")
  if (!is.null(con$identity_file)) args <- c(args, "-i", con$identity_file)
  args
}

.sh_quote <- function(x) paste0("'", gsub("'", "'\\\"'\\\"'", x, fixed = TRUE), "'")

.ssh_run <- function(con, script, timeout = NULL, allow_missing = FALSE) {
  result <- .run_command("ssh", c(.ssh_common_args(con), .ssh_target(con), script), timeout = timeout)
  .ssh_check_result(result, con, allow_missing = allow_missing)
}

.ssh_check_result <- function(result, con, allow_missing = FALSE) {
  if (result$status == 0L) return(result)
  detail <- paste(result$stderr, result$stdout)
  if (allow_missing && result$status == 44L) return(result)
  if (grepl("permission denied|authentication failed", detail, ignore.case = TRUE)) abort_netfs_auth(sprintf("SSH authentication to `%s` failed.", con$host), result = result)
  if (grepl("timed out|no route|resolve hostname|connection refused|connection closed", detail, ignore.case = TRUE)) abort_netfs_connection(sprintf("Could not connect to SSH server `%s`.", con$host), result = result)
  if (grepl("permission denied", detail, ignore.case = TRUE)) abort_netfs_permission(sprintf("SSH operation on `%s` was denied.", con$host), result = result)
  abort_netfs(sprintf("SSH operation on `%s` failed.", con$host), "netfs_backend_error", result = result)
}

.ssh_test <- function(con, path, flag) {
  result <- .ssh_run(con, sprintf("test %s %s && exit 0 || exit 44", flag, .sh_quote(path)), allow_missing = TRUE)
  result$status == 0L
}

.dir_ls.netfs_ssh <- function(con, path, ...) {
  script <- sprintf("find %s -mindepth 1 -maxdepth 1 -print", .sh_quote(path))
  result <- .ssh_run(con, script)
  values <- strsplit(result$stdout, "\r?\n")[[1L]]
  unname(vapply(values[nzchar(values)], .netfs_path_normalize, character(1)))
}

.file_exists.netfs_ssh <- function(con, path, ...) .ssh_test(con, path, "-f")
.dir_exists.netfs_ssh <- function(con, path, ...) .ssh_test(con, path, "-d")

.ssh_mutate <- function(con, command, path, result_path = path) {
  .ssh_run(con, sprintf("%s -- %s", command, .sh_quote(path)))
  invisible(result_path)
}
.dir_create.netfs_ssh <- function(con, path, ...) .ssh_mutate(con, "mkdir", path)
.dir_delete.netfs_ssh <- function(con, path, ...) .ssh_mutate(con, "rmdir", path)
.file_delete.netfs_ssh <- function(con, path, ...) .ssh_mutate(con, "rm", path)
.file_move.netfs_ssh <- function(con, path, new_path, ...) {
  .ssh_run(con, sprintf("mv -- %s %s", .sh_quote(path), .sh_quote(new_path)))
  invisible(new_path)
}
.file_copy.netfs_ssh <- function(con, path, new_path, ...) abort_netfs_unsupported("Server-side file copy is not supported by the SSH backend.", operation = "file_copy")

.file_info.netfs_ssh <- function(con, path, ...) {
  script <- sprintf("stat -c '%%F\\t%%s\\t%%Y' -- %s", .sh_quote(path))
  result <- .ssh_run(con, script)
  fields <- strsplit(sub("[\r\n]+$", "", result$stdout), "\t", fixed = TRUE)[[1L]]
  if (length(fields) < 3L) abort_netfs("SSH returned unrecognized metadata.", "netfs_parse_error")
  type <- if (grepl("directory", fields[[1L]], ignore.case = TRUE)) "directory" else if (grepl("file", fields[[1L]], ignore.case = TRUE)) "file" else fields[[1L]]
  .new_remote_info(path, type, suppressWarnings(as.numeric(fields[[2L]])),
    as.POSIXct(suppressWarnings(as.numeric(fields[[3L]])), origin = "1970-01-01", tz = "UTC"))
}

.file_download.netfs_ssh <- function(con, path, local, ...) {
  tmp <- tempfile("netfs-download-", tmpdir = dirname(fs::path_abs(local)))
  on.exit(if (fs::file_exists(tmp)) fs::file_delete(tmp), add = TRUE)
  remote <- paste0(.ssh_target(con), ":", .sh_quote(path))
  result <- .run_command("scp", c(.scp_common_args(con), remote, tmp))
  .ssh_check_result(result, con)
  if (fs::file_exists(local)) fs::file_delete(local)
  fs::file_move(tmp, local)
  invisible(local)
}

.file_upload.netfs_ssh <- function(con, local, path, ...) {
  remote <- paste0(.ssh_target(con), ":", .sh_quote(path))
  result <- .run_command("scp", c(.scp_common_args(con), local, remote))
  .ssh_check_result(result, con)
  invisible(path)
}
