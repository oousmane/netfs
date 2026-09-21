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

test_that("file existence/metadata checks use nobody=TRUE, never a full fetch", {
  # curl_fetch_memory() on an FTP file URL without nobody = TRUE downloads
  # the entire file just to check it exists - confirmed live: 18s for a
  # 22MB file vs 4s with nobody = TRUE. This must never regress.
  con <- ftp("host")
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    curl_fetch_memory = function(url, handle) {
      list(status_code = 213L, content = raw(0), headers = charToRaw("Content-Length: 42\r\nLast-Modified: Fri, 07 Aug 2026 20:44:12 GMT\r\n"))
    },
    handle_setopt = function(handle, ...) {
      opts <- list(...)
      if ("nobody" %in% names(opts)) seen$nobody <- opts$nobody
      invisible(handle)
    },
    .package = "curl"
  )
  netfs:::.ftp_metadata(con, "/data/a.csv")
  expect_true(isTRUE(seen$nobody))
})

test_that("file_info() parses real size and modification_time for FTP", {
  con <- ftp("host")
  local_mocked_bindings(
    .ftp_metadata = function(con, path) list(
      status_code = 213L, content = raw(0),
      headers = charToRaw("Content-Length: 22762048\r\nLast-Modified: Fri, 07 Aug 2026 20:44:12 GMT\r\n")
    ),
    .package = "netfs"
  )
  info <- netfs:::.file_info.netfs_ftp(con, "/data/a.csv")
  expect_equal(as.character(info$type), "file")
  expect_equal(as.numeric(info$size), 22762048)
  expect_equal(info$modification_time, as.POSIXct("2026-08-07 20:44:12", tz = "UTC"))
})

test_that("file_info() falls back to directory type when metadata isn't available", {
  con <- ftp("host")
  local_mocked_bindings(
    .ftp_metadata = function(con, path) rlang::abort("not found", class = c("netfs_not_found", "netfs_error")),
    .dir_exists.netfs_ftp = function(con, path, ...) TRUE,
    .package = "netfs"
  )
  info <- netfs:::.file_info.netfs_ftp(con, "/data")
  expect_equal(as.character(info$type), "directory")
  expect_true(is.na(info$size))
})
