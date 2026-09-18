test_that("connection constructors validate and redact", {
  local_mocked_bindings(
    .keyring_set_with_value = function(...) invisible(NULL),
    .package = "netfs"
  )
  x <- ssh("server.example.org", user = "alice", password = "secret")
  expect_s3_class(x, "netfs_ssh")
  expect_equal(x$port, 22L)
  expect_null(x$password)
  expect_output(print(x), "server.example.org")
  expect_false(any(grepl("secret", capture.output(print(x)), fixed = TRUE)))
  expect_error(ftp(""), class = "netfs_validation_error")
  expect_error(ftp("host", port = 70000), class = "netfs_validation_error")
})

test_that("SMB shares are normalized", {
  x <- smb("fileserver", "/DATA/")
  expect_equal(x$share, "DATA")
  expect_s3_class(x, "netfs_smb")
  expect_output(print(x), "share: DATA", fixed = TRUE)
})
