test_that("SMB machine listings normalize metadata", {
  fixture <- paste0(
    "  .                                   D        0  Mon Jan  1 00:00:00 2024\n",
    "  ..                                  D        0  Mon Jan  1 00:00:00 2024\n",
    "  file with spaces.txt                A      123  Mon Jan  1 00:00:00 2024\n",
    "  folder                              D        0  Mon Jan  1 00:00:00 2024\n",
    "  a_very_long_filename_that_overflows_the_padded_name_column.pdf      A 45725478  Mon Jan  1 00:00:00 2024\n",
    "\t\t141537791 blocks of size 4096. 74507669 blocks available\n"
  )
  x <- netfs:::.smb_parse_listing(fixture, "/data")
  expect_equal(as.character(x$path), c(
    "/data/file with spaces.txt", "/data/folder",
    "/data/a_very_long_filename_that_overflows_the_padded_name_column.pdf"
  ))
  expect_equal(as.character(x$type), c("file", "directory", "file"))
  expect_equal(as.numeric(x$size), c(123, 0, 45725478))
})

test_that("remote file_info is typed like fs::file_info()", {
  x <- netfs:::.smb_parse_listing(
    "  report.csv                          A      123  Mon Jan  1 00:00:00 2024\n", "/data"
  )
  expect_s3_class(x$path, "fs_path")
  expect_s3_class(x$type, "factor")
  expect_equal(levels(x$type), netfs:::.remote_file_type_levels)
  expect_s3_class(x$size, "fs_bytes")
})

test_that("SMB passwords are absent from argument construction", {
  local_mocked_bindings(
    .keyring_set_with_value = function(...) invisible(NULL),
    .package = "netfs"
  )
  x <- smb("host", "share", user = "alice", password = "secret")
  expect_null(x$password)
  expect_false(any(grepl("secret", netfs:::.smb_common_args(x), fixed = TRUE)))
})

test_that("smbclient runs with a password inherit the parent PATH", {
  con <- smb("fileserver", "DATA", user = "alice")
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .require_smbclient = function() invisible(TRUE),
    .connection_password = function(...) "secret",
    .run_command = function(command, args = character(), env = NULL, ...) {
      seen$env <- env
      list(status = 0L, stdout = "", stderr = "")
    },
    .package = "netfs"
  )
  netfs:::.smb_run(con, "ls")
  expect_true("current" %in% seen$env)
  expect_equal(unname(seen$env[names(seen$env) == "PASSWD"]), "secret")
})

test_that("unrecognized SMB failures include the smbclient output in the message", {
  con <- smb("fileserver", "DATA")
  local_mocked_bindings(
    .require_smbclient = function() invisible(TRUE),
    .connection_password = function(...) NULL,
    .run_command = function(...) list(status = 1L, stdout = "", stderr = "NT_STATUS_CONNECTION_REFUSED"),
    .package = "netfs"
  )
  expect_error(
    netfs:::.smb_run(con, "ls"),
    "NT_STATUS_CONNECTION_REFUSED",
    class = "netfs_connection_error"
  )
})

test_that("dir_ls accepts a connection as remote-root shorthand", {
  con <- smb("fileserver", "DATA")
  local_mocked_bindings(
    .dir_ls = function(con, path, ...) path,
    .package = "netfs"
  )
  expect_equal(dir_ls(con), fs::as_fs_path("/"))
  expect_equal(dir_ls(con = con), fs::as_fs_path("/"))
})

test_that("dir_ls on a subdirectory lists its contents, not just its own entry", {
  con <- smb("fileserver", "DATA")
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .smb_run = function(con, command) { seen$command <- command; list(status = 0L, stdout = "") },
    .package = "netfs"
  )
  netfs:::.dir_ls.netfs_smb(con, "/DEMANDES_DONNEES")
  expect_match(seen$command, "\\\\\\*\"$")

  netfs:::.dir_ls.netfs_smb(con, "/")
  expect_equal(seen$command, "ls")
})

test_that("dir_ls(type=) filters by type without extra round trips on SMB", {
  con <- smb("fileserver", "DATA")
  fixture <- paste0(
    "  a.txt                               A       10  Mon Jan  1 00:00:00 2024\n",
    "  sub                                  D        0  Mon Jan  1 00:00:00 2024\n"
  )
  calls <- 0L
  local_mocked_bindings(
    .smb_run = function(con, command) { calls <<- calls + 1L; list(status = 0L, stdout = fixture) },
    .package = "netfs"
  )
  expect_equal(dir_ls("/data", con = con, type = "file"), fs::as_fs_path("/data/a.txt"))
  expect_equal(dir_ls("/data", con = con, type = "directory"), fs::as_fs_path("/data/sub"))
  expect_equal(calls, 2L)
})

test_that("remote mutating operations return fs_path like their fs counterparts", {
  con <- smb("fileserver", "DATA")
  local_mocked_bindings(
    .dir_create = function(con, path, ...) invisible(path),
    .dir_delete = function(con, path, ...) invisible(path),
    .file_delete = function(con, path, ...) invisible(path),
    .file_copy = function(con, path, new_path, ...) invisible(new_path),
    .file_move = function(con, path, new_path, ...) invisible(new_path),
    .package = "netfs"
  )
  expect_equal(dir_create("/data", con = con), fs::as_fs_path("/data"))
  expect_equal(dir_delete("/data", con = con), fs::as_fs_path("/data"))
  expect_equal(file_delete("/data/a.csv", con = con), fs::as_fs_path("/data/a.csv"))
  expect_equal(file_copy("/data/a.csv", "/data/b.csv", con = con), fs::as_fs_path("/data/b.csv"))
  expect_equal(file_move("/data/a.csv", "/data/b.csv", con = con), fs::as_fs_path("/data/b.csv"))
})

test_that("missing Linux SMB clients provide installation guidance", {
  local_mocked_bindings(
    .has_smbclient = function() FALSE,
    .is_macos = function() FALSE,
    .package = "netfs"
  )

  expect_error(
    netfs:::.require_smbclient(),
    "smbclient or samba-client",
    class = "netfs_backend_unavailable"
  )
})

test_that("missing macOS SMB clients suggest Homebrew installation", {
  local_mocked_bindings(
    .has_smbclient = function() FALSE,
    .is_macos = function() TRUE,
    .package = "netfs"
  )

  expect_error(
    netfs:::.require_smbclient(),
    "brew install samba",
    class = "netfs_backend_unavailable"
  )
})

test_that("macOS SMB operations use smbclient rather than native mounting", {
  local_mocked_bindings(
    .is_windows = function() FALSE,
    .is_macos = function() TRUE,
    .package = "netfs"
  )
  expect_false(netfs:::.smb_uses_native_fs())
})
