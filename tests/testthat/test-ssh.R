test_that("SSH targets and arguments are constructed safely", {
  x <- ssh("host", user = "alice", port = 2200, identity_file = "key file")
  expect_equal(netfs:::.ssh_target(x), "alice@host")
  expect_true(all(c("2200", "key file") %in% netfs:::.ssh_common_args(x)))
})

test_that("scp is forced onto the legacy protocol, so transfers stay shell-routed like every other SSH operation", {
  # Without this, a modern OpenSSH client's default SFTP transfer is served
  # by a separate process on some remotes (e.g. Windows OpenSSH's native
  # sftp-server) that can disagree with the login shell (e.g. Git Bash)
  # about whether a path even exists.
  expect_true("-O" %in% netfs:::.scp_common_args(ssh("host")))
})

test_that("scp remote paths are backslash-escaped, not shell-quoted", {
  # Confirmed live: scp does no escaping of its own when it embeds the path
  # into the `scp -t/-f <path>` command it sends over the channel, and (for
  # downloads) compares the server's reported filename against this same
  # raw string using backslash-aware parsing - wrapping it in quotes like
  # .sh_quote() does would leave literal quote characters in what scp
  # expects, and it would never match what the server reports back.
  expect_equal(netfs:::.scp_path_escape("/data/a file.txt"), "/data/a\\ file.txt")
  expect_equal(netfs:::.scp_path_escape("/data/a (b) & c.txt"), "/data/a\\ \\(b\\)\\ \\&\\ c.txt")
  expect_equal(netfs:::.scp_path_escape("/data/plain.txt"), "/data/plain.txt")
})

test_that("SSH/SCP calls share one ControlMaster connection on Unix, none on Windows", {
  con <- ssh("host", user = "alice", port = 22)
  args <- netfs:::.ssh_common_args(con)
  expect_true(any(grepl("^ControlMaster=auto$", args)))
  ssh_path <- args[which(grepl("^ControlPath=", args))]
  scp_path <- netfs:::.scp_common_args(con)[which(grepl("^ControlPath=", netfs:::.scp_common_args(con)))]
  expect_equal(ssh_path, scp_path) # same connection, same socket, whichever tool is used

  local_mocked_bindings(
    .Platform = list(OS.type = "windows"),
    .package = "base"
  )
  expect_equal(netfs:::.ssh_control_args(con), character())
})

test_that("unrecognized SSH failures include the remote command's own output", {
  con <- ssh("host")
  result <- list(status = 1L, stdout = "", stderr = "mkdir: cannot create directory 'x': No space left on device")
  expect_error(
    netfs:::.ssh_check_result(result, con),
    "No space left on device",
    class = "netfs_backend_error"
  )
})

test_that("a bare file-level 'permission denied' is not misclassified as an auth failure", {
  con <- ssh("host")
  file_level <- list(status = 1L, stdout = "", stderr = "mkdir: cannot create directory 'x': Permission denied")
  expect_error(netfs:::.ssh_check_result(file_level, con), class = "netfs_permission_error")

  auth_level <- list(status = 255L, stdout = "", stderr = "hpc@host: Permission denied (publickey,password).")
  expect_error(netfs:::.ssh_check_result(auth_level, con), class = "netfs_auth_error")
})

test_that("SSH listing parsing handles spaces", {
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) list(status = 0L, stdout = "/data/a b\n/data/c\n", stderr = ""),
    .package = "netfs"
  )
  expect_equal(dir_ls("/data", con = ssh("host")), fs::as_fs_path(c("/data/a b", "/data/c")))
})

test_that("file_info() falls back to BSD stat syntax for non-Linux remotes", {
  # `stat -c` is GNU-coreutils-specific; confirmed locally that macOS's
  # BSD stat errors on it ("illegal option -- c"). The script must try
  # both, since netfs doesn't know the remote OS in advance.
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) { seen$script <- script; list(status = 0L, stdout = "Regular File\t213\t1755321821\n", stderr = "") },
    .package = "netfs"
  )
  info <- netfs:::.file_info.netfs_ssh(ssh("host"), "/etc/hosts")
  expect_match(seen$script, "stat -c ", fixed = TRUE)
  expect_match(seen$script, "stat -f ", fixed = TRUE)
  expect_equal(as.character(info$type), "file")
  expect_equal(as.numeric(info$size), 213)
})

test_that("the GNU stat format string uses a real tab byte, not the \\t escape sequence", {
  # Confirmed live: a Windows/MSYS2-packaged GNU coreutils stat does not
  # interpret `\t` (backslash, t) as an escape the way Linux's does - it
  # prints those two characters verbatim, so `strsplit(..., "\t")` never
  # finds a real tab and file_info() fails with "unrecognized metadata".
  # A literal tab byte in the format string sidesteps stat's escape
  # handling entirely.
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) { seen$script <- script; list(status = 0L, stdout = "regular file\t213\t1755321821\n", stderr = "") },
    .package = "netfs"
  )
  netfs:::.file_info.netfs_ssh(ssh("host"), "/etc/hosts")
  gnu_clause <- sub(" \\|\\|.*", "", seen$script)
  expect_false(grepl("\\\\t", gnu_clause, fixed = TRUE))
  expect_match(gnu_clause, "%F\t%s\t%Y", fixed = TRUE)
})

test_that("file_info() recognizes a symlink instead of reporting NA for it", {
  # GNU's %F and BSD's %HT both describe a symlink as some form of
  # "symbolic link" - previously matched neither the "directory" nor "file"
  # branch, so a symlink's type silently came back NA.
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) list(status = 0L, stdout = "symbolic link\t0\t1755321821\n", stderr = ""),
    .package = "netfs"
  )
  info <- netfs:::.file_info.netfs_ssh(ssh("host"), "/etc/hosts")
  expect_equal(as.character(info$type), "symlink")
})

test_that("a missing remote path is classified netfs_not_found, not a generic backend error", {
  # Every coreutils tool (stat, rm, chmod, readlink, ...) reports a missing
  # target with this same phrase.
  result <- list(status = 1L, stdout = "", stderr = "stat: cannot stat '/nope': No such file or directory")
  expect_error(netfs:::.ssh_check_result(result, ssh("host")), class = "netfs_not_found")
})

test_that("file_chmod() converts any fs_perms-accepted mode to octal for chmod", {
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) { seen$script <- script; list(status = 0L, stdout = "", stderr = "") },
    .package = "netfs"
  )
  netfs:::.file_chmod.netfs_ssh(ssh("host"), "/f", "644")
  expect_match(seen$script, "chmod 644 -- ", fixed = TRUE)
  netfs:::.file_chmod.netfs_ssh(ssh("host"), "/f", "u=rwx,go=rx")
  expect_match(seen$script, "chmod 755 -- ", fixed = TRUE)
})

test_that("file_chown() builds a uid[:gid] spec and requires at least one of them", {
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) { seen$script <- script; list(status = 0L, stdout = "", stderr = "") },
    .package = "netfs"
  )
  netfs:::.file_chown.netfs_ssh(ssh("host"), "/f", user_id = 1000, group_id = 100)
  expect_match(seen$script, "chown 1000:100 -- ", fixed = TRUE)
  netfs:::.file_chown.netfs_ssh(ssh("host"), "/f", user_id = 1000)
  expect_match(seen$script, "chown 1000 -- ", fixed = TRUE)
  expect_error(netfs:::.file_chown.netfs_ssh(ssh("host"), "/f"), class = "netfs_validation_error")
})

test_that("file_touch() uses a portable plain touch for 'now', and GNU -d only for an explicit timestamp", {
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) { seen$script <- script; list(status = 0L, stdout = "", stderr = "") },
    .package = "netfs"
  )
  netfs:::.file_touch.netfs_ssh(ssh("host"), "/f")
  expect_equal(trimws(sub("--.*", "", seen$script)), "touch")

  netfs:::.file_touch.netfs_ssh(ssh("host"), "/f", access_time = as.POSIXct("2020-01-02 03:04:05", tz = "UTC"))
  expect_match(seen$script, "touch -a -d ", fixed = TRUE)
  expect_match(seen$script, "2020-01-02T03:04:05", fixed = TRUE)
})

test_that("file_access() combines test -r/-w/-x and rejects an unknown mode", {
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) { seen$script <- script; list(status = 0L, stdout = "", stderr = "") },
    .package = "netfs"
  )
  netfs:::.file_access.netfs_ssh(ssh("host"), "/f", c("read", "write"))
  expect_match(seen$script, "test -r -- ", fixed = TRUE)
  expect_match(seen$script, "test -w -- ", fixed = TRUE)
  expect_error(netfs:::.file_access.netfs_ssh(ssh("host"), "/f", "fly"), class = "netfs_validation_error")
})

test_that("file_copy() uses cp on the remote shell instead of local download+upload staging", {
  # A same-server copy never needs to leave the remote machine - it has its
  # own shell (the same one every other SSH operation already runs
  # through), so cp -- source dest is both correct and far cheaper than
  # staging the file through this machine.
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) { seen$script <- script; list(status = 0L, stdout = "", stderr = "") },
    .package = "netfs"
  )
  netfs:::.file_copy.netfs_ssh(ssh("host"), "/a", "/b")
  expect_match(seen$script, "^cp -- ", perl = TRUE)
})

test_that("link_create()/link_path()/link_delete() shell out to ln -s/readlink/rm", {
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) { seen$script <- script; list(status = 0L, stdout = "/target\n", stderr = "") },
    .package = "netfs"
  )
  netfs:::.link_create.netfs_ssh(ssh("host"), "/target", "/link")
  expect_match(seen$script, "^ln -s -- ", perl = TRUE)

  netfs:::.link_create.netfs_ssh(ssh("host"), "/target", "/link", symbolic = FALSE)
  expect_match(seen$script, "^ln -- ", perl = TRUE)

  expect_equal(as.character(netfs:::.link_path.netfs_ssh(ssh("host"), "/link")), "/target")
  expect_match(seen$script, "^readlink -- ", perl = TRUE)

  netfs:::.link_delete.netfs_ssh(ssh("host"), "/link")
  expect_match(seen$script, "^rm -- ", perl = TRUE)
})
