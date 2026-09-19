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

test_that(".ftp_request uses the caller's configured handle, not a fresh one", {
  seen <- new.env(parent = emptyenv())
  handle_id <- 0L
  local_mocked_bindings(
    new_handle = function(...) { handle_id <<- handle_id + 1L; structure(list(id = handle_id), class = "fake_curl_handle") },
    handle_setopt = function(handle, ...) {
      prior <- if (is.null(seen$opts)) list() else seen$opts
      seen$opts <- utils::modifyList(prior, list(...))
      seen$configured_handle <- handle
      invisible(handle)
    },
    curl_fetch_memory = function(url, handle) { seen$used_handle <- handle; list(status_code = 200L, content = raw(0)) },
    .package = "curl"
  )

  con <- ftp("host")
  netfs:::.dir_ls.netfs_ftp(con, "/data")
  expect_identical(seen$used_handle, seen$configured_handle)
  expect_true(isTRUE(seen$opts$dirlistonly))

  seen$opts <- NULL
  netfs:::.ftp_quote(con, "MKD", "/data/new", "directory creation")
  expect_identical(seen$used_handle, seen$configured_handle)
  expect_equal(seen$opts$quote, "MKD /data/new")
})
