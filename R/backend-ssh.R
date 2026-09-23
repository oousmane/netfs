.ssh_target <- function(con) if (is.null(con$user)) con$host else paste0(con$user, "@", con$host)

# Each netfs SSH call previously opened a brand-new connection (full
# handshake + auth) - dir_ls(), every file_info() call, etc. OpenSSH's
# ControlMaster lets the first call become a persistent master connection
# that later calls transparently multiplex through, with no separate setup
# step required and no credential ever touching netfs. Windows OpenSSH has
# had unreliable/absent ControlMaster support, so this only applies on
# Unix; Windows keeps the previous one-connection-per-call behavior.
.ssh_control_path <- function(con) {
  key <- paste0(con$user %||% "", "@", con$host, ":", con$port)
  # /tmp directly, not tempdir(): tempdir()'s path on macOS is long enough
  # to risk exceeding the ~104-byte Unix domain socket path limit once a
  # descriptive filename is appended.
  file.path("/tmp", paste0("netfs-ssh-", substr(rlang::hash(key), 1, 16)))
}

.ssh_control_args <- function(con) {
  if (.Platform$OS.type == "windows") return(character())
  c("-o", "ControlMaster=auto", "-o", paste0("ControlPath=", .ssh_control_path(con)), "-o", "ControlPersist=10m")
}

.ssh_common_args <- function(con) {
  args <- c("-p", as.character(con$port), "-o", "BatchMode=yes", .ssh_control_args(con))
  if (!is.null(con$identity_file)) args <- c(args, "-i", con$identity_file)
  args
}

.scp_common_args <- function(con) {
  # -O: force the legacy SCP wire protocol, which every OpenSSH server has
  # supported for decades by simply invoking `scp -t/-f` through the login
  # shell. Since OpenSSH 9.0 (2022), the client defaults to SFTP instead,
  # which on Windows OpenSSH is served by a separate, native sftp-server
  # process that knows nothing about a Git-Bash/MSYS2 remote shell's `/c/`
  # path translation - `test -d`/`find`/etc. (run through that shell) and
  # an SFTP-protocol scp then disagree about whether a path exists at all.
  # -O keeps file transfers on the same shell-routed path resolution as
  # every other SSH operation.
  args <- c("-O", "-P", as.character(con$port), "-o", "BatchMode=yes", .ssh_control_args(con))
  if (!is.null(con$identity_file)) args <- c(args, "-i", con$identity_file)
  args
}

.sh_quote <- function(x) paste0("'", gsub("'", "'\\\"'\\\"'", x, fixed = TRUE), "'")

# scp's `user@host:path` target argument is never parsed by a shell locally
# (it's a single argv string) and scp does no escaping of its own when it
# embeds `path` into the `scp -t/-f <path>` command it sends over the SSH
# channel - so it must arrive already escaped for the remote shell, and it
# must NOT be wrapped like .sh_quote() does: for downloads, scp's own
# client-side check that the server's reported filename matches what was
# requested (hardening against a server sending back a different file)
# derives the "requested" name from this same raw argv string using
# backslash-aware parsing, not full shell-quote parsing - literal quote
# characters would end up part of the "expected" name and never match.
# Confirmed live against a Windows OpenSSH/Git-Bash remote (upload and
# download, including a path with spaces and parens).
.scp_path_escape <- function(x) gsub("([][ !\"$&'()*;<>?`|\\\\])", "\\\\\\1", x, perl = TRUE)

.ssh_run <- function(con, script, timeout = NULL, allow_missing = FALSE) {
  result <- .run_command("ssh", c(.ssh_common_args(con), .ssh_target(con), script), timeout = timeout)
  .ssh_check_result(result, con, allow_missing = allow_missing)
}

.ssh_check_result <- function(result, con, allow_missing = FALSE) {
  if (result$status == 0L) return(result)
  detail <- paste(result$stderr, result$stdout)
  if (allow_missing && result$status == 44L) return(result)
  # OpenSSH's own connection-level denial names the auth methods tried,
  # e.g. "Permission denied (publickey,password)." - that parenthetical is
  # what distinguishes it from a bare "Permission denied" a remote command
  # like mkdir/rm prints for a file-level permission problem after a
  # successful login. Without requiring it, the file-level case below was
  # dead code: any "permission denied" text always matched this branch
  # first.
  if (grepl("permission denied \\(|authentication failed", detail, ignore.case = TRUE)) abort_netfs_auth(sprintf("SSH authentication to `%s` failed.", con$host), result = result)
  if (grepl("timed out|no route|resolve hostname|connection refused|connection closed", detail, ignore.case = TRUE)) abort_netfs_connection(sprintf("Could not connect to SSH server `%s`.", con$host), result = result)
  if (grepl("permission denied", detail, ignore.case = TRUE)) abort_netfs_permission(sprintf("SSH operation on `%s` was denied.", con$host), result = result)
  # Every coreutils tool tested (stat, rm, mv, chmod, chown, readlink, ...)
  # reports a missing target with this same phrase. Without this, file_info()
  # and friends surfaced a missing remote path as a generic
  # netfs_backend_error instead of netfs_not_found, unlike every other
  # backend.
  if (grepl("no such file or directory", detail, ignore.case = TRUE)) abort_netfs_not_found(sprintf("Remote path was not found on `%s`.", con$host), result = result)
  detail <- trimws(detail)
  message <- if (nzchar(detail)) {
    sprintf("SSH operation on `%s` failed: %s", con$host, detail)
  } else {
    sprintf("SSH operation on `%s` failed.", con$host)
  }
  abort_netfs(message, "netfs_backend_error", result = result)
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
.file_copy.netfs_ssh <- function(con, path, new_path, ...) {
  .ssh_run(con, sprintf("cp -- %s %s", .sh_quote(path), .sh_quote(new_path)))
  invisible(new_path)
}

.file_info.netfs_ssh <- function(con, path, ...) {
  # `stat -c` is GNU-coreutils-specific (illegal option on macOS/BSD's
  # stat, confirmed locally). Falls back to BSD's stat -f syntax, which
  # uses different flags entirely; %HT/%z/%m give the same three fields
  # (type/size/epoch mtime) in BSD's own format.
  #
  # The GNU branch's format string uses a literal tab byte between fields
  # (R's `\t`), not the two-character `\t` escape sequence - GNU stat's
  # format-string engine is documented to convert that escape to a real
  # tab, but a Windows/MSYS2-packaged GNU coreutils stat (confirmed live)
  # doesn't, and prints it verbatim instead, breaking the split below. A
  # literal tab byte needs no such interpretation from `stat` at all: any
  # character not part of a `%` sequence is passed through unchanged on
  # every `stat` implementation tested.
  quoted <- .sh_quote(path)
  script <- sprintf("stat -c '%%F\t%%s\t%%Y' -- %s 2>/dev/null || stat -f '%%HT%%t%%z%%t%%m' -- %s", quoted, quoted)
  result <- .ssh_run(con, script)
  fields <- strsplit(sub("[\r\n]+$", "", result$stdout), "\t", fixed = TRUE)[[1L]]
  if (length(fields) < 3L) abort_netfs("SSH returned unrecognized metadata.", "netfs_parse_error")
  # GNU's %F and BSD's %HT both describe a symlink as "(S|s)ymbolic (L|l)ink"
  # - checked before "file"/"directory" only for clarity; neither of those
  # substrings actually appears in that phrase on either platform.
  type <- if (grepl("directory", fields[[1L]], ignore.case = TRUE)) "directory"
    else if (grepl("link", fields[[1L]], ignore.case = TRUE)) "symlink"
    else if (grepl("file", fields[[1L]], ignore.case = TRUE)) "file"
    else fields[[1L]]
  .new_remote_info(path, type, suppressWarnings(as.numeric(fields[[2L]])),
    as.POSIXct(suppressWarnings(as.numeric(fields[[3L]])), origin = "1970-01-01", tz = "UTC"))
}

.file_download.netfs_ssh <- function(con, path, local, ...) {
  tmp <- tempfile("netfs-download-", tmpdir = dirname(fs::path_abs(local)))
  on.exit(if (fs::file_exists(tmp)) fs::file_delete(tmp), add = TRUE)
  remote <- paste0(.ssh_target(con), ":", .scp_path_escape(path))
  result <- .run_command("scp", c(.scp_common_args(con), remote, tmp))
  .ssh_check_result(result, con)
  if (fs::file_exists(local)) fs::file_delete(local)
  fs::file_move(tmp, local)
  invisible(local)
}

.file_upload.netfs_ssh <- function(con, local, path, ...) {
  remote <- paste0(.ssh_target(con), ":", .scp_path_escape(path))
  result <- .run_command("scp", c(.scp_common_args(con), local, remote))
  .ssh_check_result(result, con)
  invisible(path)
}

.file_chmod.netfs_ssh <- function(con, path, mode, ...) {
  octal <- sprintf("%o", unclass(fs::as_fs_perms(mode)))
  .ssh_run(con, sprintf("chmod %s -- %s", octal, .sh_quote(path)))
  invisible(path)
}

.file_chown.netfs_ssh <- function(con, path, user_id = NULL, group_id = NULL, ...) {
  if (is.null(user_id) && is.null(group_id)) {
    rlang::abort("At least one of `user_id` or `group_id` must be supplied.", class = "netfs_validation_error")
  }
  spec <- paste0(user_id %||% "", if (!is.null(group_id)) paste0(":", group_id) else "")
  .ssh_run(con, sprintf("chown %s -- %s", spec, .sh_quote(path)))
  invisible(path)
}

.file_touch.netfs_ssh <- function(con, path, access_time = Sys.time(), modification_time = access_time, ...) {
  quoted <- .sh_quote(path)
  now <- Sys.time()
  is_now <- function(t) isTRUE(abs(as.numeric(t) - as.numeric(now)) < 5)
  if (is_now(access_time) && is_now(modification_time)) {
    # A plain `touch` (both times default to "now") needs no date syntax at
    # all - portable across every `touch` implementation, GNU or BSD.
    .ssh_run(con, sprintf("touch -- %s", quoted))
  } else {
    # GNU-only: `-d` accepts an ISO 8601 timestamp directly, confirmed live
    # against a GNU coreutils remote. BSD/macOS touch has no `-d` at all -
    # it uses `-t [[CC]YY]MMDDhhmm[.SS]` in the *server's local time*, which
    # this session had no reachable BSD/macOS SSH target to verify a
    # correct UTC conversion against; a wrong guess there would silently
    # set the wrong timestamp, which is worse than failing outright, so
    # arbitrary timestamps are left GNU-only rather than guessed at.
    a <- format(access_time, "%Y-%m-%dT%H:%M:%S", tz = "UTC")
    m <- format(modification_time, "%Y-%m-%dT%H:%M:%S", tz = "UTC")
    .ssh_run(con, sprintf("touch -a -d %s -m -d %s -- %s", .sh_quote(a), .sh_quote(m), quoted))
  }
  invisible(path)
}

.file_access.netfs_ssh <- function(con, path, mode, ...) {
  flags <- c(read = "-r", write = "-w", execute = "-x")
  unknown <- setdiff(mode, names(flags))
  if (length(unknown)) {
    rlang::abort(sprintf("Unknown file_access() mode(s): %s", paste(unknown, collapse = ", ")), class = "netfs_validation_error")
  }
  script <- paste(sprintf("test %s -- %s", flags[mode], .sh_quote(path)), collapse = " && ")
  result <- .ssh_run(con, sprintf("%s && exit 0 || exit 44", script), allow_missing = TRUE)
  result$status == 0L
}

.link_create.netfs_ssh <- function(con, path, new_path, symbolic = TRUE, ...) {
  command <- if (isTRUE(symbolic)) "ln -s" else "ln"
  .ssh_run(con, sprintf("%s -- %s %s", command, .sh_quote(path), .sh_quote(new_path)))
  invisible(new_path)
}

.link_path.netfs_ssh <- function(con, path, ...) {
  result <- .ssh_run(con, sprintf("readlink -- %s", .sh_quote(path)))
  fs::as_fs_path(trimws(result$stdout))
}

.link_delete.netfs_ssh <- function(con, path, ...) .file_delete.netfs_ssh(con, path)
