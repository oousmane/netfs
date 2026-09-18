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
