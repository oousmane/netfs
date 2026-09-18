test_that("SMB machine listings normalize metadata", {
  fixture <- "A|file with spaces.txt|123|Mon Jan  1 00:00:00 2024\nD|folder|0|Mon Jan  1 00:00:00 2024\n"
  x <- netfs:::.smb_parse_listing(fixture, "/data")
  expect_equal(x$path, c("/data/file with spaces.txt", "/data/folder"))
  expect_equal(x$type, c("file", "directory"))
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

test_that("dir_ls accepts a connection as remote-root shorthand", {
  con <- smb("fileserver", "DATA")
  local_mocked_bindings(
    .dir_ls = function(con, path, ...) path,
    .package = "netfs"
  )
  expect_equal(dir_ls(con), "/")
  expect_equal(dir_ls(con = con), "/")
})

test_that("missing Linux SMB clients provide installation guidance", {
  local_mocked_bindings(
    .has_smbclient = function() FALSE,
    .package = "netfs"
  )

  expect_error(
    netfs:::.require_smbclient(),
    "smbclient or samba-client",
    class = "netfs_backend_unavailable"
  )
})

test_that("macOS mounts SMB natively without exposing passwords in arguments", {
  seen <- new.env(parent = emptyenv())
  con <- smb("fileserver", "DATA", user = "alice", domain = "WORK")
  local_mocked_bindings(
    .connection_password = function(...) "top-secret",
    .run_command = function(command, args = character(), ...) {
      seen$command <- command
      seen$args <- args
      seen$options <- list(...)
      list(status = 0L, stdout = "/Volumes/DATA/\n", stderr = "")
    },
    .package = "netfs"
  )

  expect_equal(netfs:::.smb_macos_mount(con), "/Volumes/DATA/")
  expect_equal(seen$command, "/usr/bin/osascript")
  expect_equal(seen$args, "-")
  expect_false(grepl("top-secret", paste(seen$command, seen$args), fixed = TRUE))
  expect_match(seen$options$stdin, "with password")
  expect_match(seen$options$stdin, "top-secret", fixed = TRUE)
  expect_equal(seen$options$redact, "top-secret")
})

test_that("macOS SMB paths resolve inside the mounted share", {
  con <- smb("fileserver", "DATA")
  local_mocked_bindings(
    .smb_macos_mount = function(...) "/Volumes/DATA",
    .is_windows = function() FALSE,
    .package = "netfs"
  )
  expect_equal(
    as.character(netfs:::.smb_native_path(con, "/folder/report.csv")),
    as.character(fs::path("/Volumes/DATA", "folder", "report.csv"))
  )
})
