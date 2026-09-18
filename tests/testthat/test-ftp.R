test_that("FTP URLs encode path components and omit credentials", {
  local_mocked_bindings(
    .keyring_set_with_value = function(...) invisible(NULL),
    .package = "netfs"
  )
  x <- ftp("ftp://example.org", user = "alice", password = "secret", tls = TRUE)
  url <- netfs:::.ftp_url(x, "/a b/file.csv")
  expect_match(url, "a%20b/file.csv", fixed = TRUE)
  expect_false(grepl("secret", url, fixed = TRUE))
  expect_equal(
    netfs:::.ftp_url(x, "/a b/"),
    "ftp://example.org:21/a%20b/"
  )
})
