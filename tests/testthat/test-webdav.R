test_that("webdav() validates the URL and normalizes a trailing slash", {
  con <- webdav("https://cloud.example.org/dav/alice", user = "alice")
  expect_true(inherits(con, "netfs_webdav"))
  expect_equal(con$url, "https://cloud.example.org/dav/alice/")
  expect_error(webdav("ftp://example.org/"), class = "netfs_validation_error")
})

test_that("path helpers convert between netfs paths and the webdav package's own conventions", {
  expect_null(netfs:::.webdav_relpath("/"))
  expect_equal(netfs:::.webdav_relpath("/a/b.txt"), "a/b.txt")
  expect_equal(netfs:::.webdav_url_path("https://host/dav/alice/"), "/dav/alice/")
  expect_equal(netfs:::.webdav_url_path("https://host/"), "/")

  con <- list(url = "https://host/dav/alice/")
  # Confirmed live: hrefs are always absolute from the *server's* own root,
  # never relative to whatever base_url/folder_path was queried with.
  expect_equal(netfs:::.webdav_to_netfs_path(con, "/dav/alice/reports/a.txt"), "/reports/a.txt")
  expect_equal(netfs:::.webdav_to_netfs_path(con, "/dav/alice/reports/"), "/reports")

  # RFC 4918 permits <href> to be a full absolute URL instead of a
  # server-relative path, server's choice. Confirmed live: WsgiDAV returns
  # the relative form (tested above), IT Hit's .NET WebDAV Server (at
  # webdavserver.net) returns the absolute form - which, unhandled, left
  # the scheme and host embedded as bogus leading path segments.
  root_con <- list(url = "http://webdavserver.net/")
  expect_equal(
    netfs:::.webdav_to_netfs_path(root_con, "http://webdavserver.net/netfs-test/a.txt"),
    "/netfs-test/a.txt"
  )
})

test_that(".webdav_run() translates both a thrown condition and a warning+sentinel failure the same way", {
  # webdav_create_directory()/webdav_copy_file()/webdav_download_file() throw
  # on failure; webdav_upload_file()/webdav_list_files()/
  # webdav_delete_resource() never do - they warn and return FALSE/NULL
  # instead (confirmed live against a real server). Both must end up
  # classified the same way by netfs.
  con <- list(url = "https://host/")
  throwing <- function() stop("HTTP 404 Not Found.")
  warning_returning <- function() { warning("HTTP 404 Not Found."); NULL }

  expect_error(netfs:::.webdav_run(con, throwing()), class = "netfs_not_found")
  expect_error(netfs:::.webdav_run(con, warning_returning()), class = "netfs_not_found")

  # A successful, validly empty result (an empty directory listing) must
  # not be misread as a failure.
  expect_equal(netfs:::.webdav_run(con, tibble::tibble()), tibble::tibble())
})

test_that(".webdav_translate() classifies HTTP statuses and transport failures into the right condition", {
  con <- list(url = "https://host/")
  expect_error(netfs:::.webdav_translate(con, "HTTP 404 Not Found."), class = "netfs_not_found")
  expect_error(netfs:::.webdav_translate(con, "HTTP 401 Unauthorized."), class = "netfs_auth_error")
  expect_error(netfs:::.webdav_translate(con, "HTTP 403 Forbidden."), class = "netfs_permission_error")
  expect_error(netfs:::.webdav_translate(con, "Could not connect to server [host]"), class = "netfs_connection_error")
  expect_error(netfs:::.webdav_translate(con, "Could not resolve hostname [host]"), class = "netfs_connection_error")
  expect_error(netfs:::.webdav_translate(con, "something else entirely"), class = "netfs_backend_error")
})

test_that(".webdav_stat() distinguishes a file, a directory, and a missing path by listing the parent", {
  # webdav_list_files() drops its own queried path's entry (it assumes that
  # first row is always the collection itself) - so a file and an empty
  # directory both list as zero rows if queried directly, indistinguishable
  # from each other. The only reliable signal is the parent's own listing.
  con <- webdav("https://host/")
  local_mocked_bindings(
    .dir_info = function(con, path, ...) {
      if (identical(path, "/")) {
        return(tibble::tibble(
          path = fs::as_fs_path(c("/a.txt", "/sub")),
          type = factor(c("file", "directory"), levels = netfs:::.remote_file_type_levels),
          size = fs::as_fs_bytes(c(10, NA)),
          modification_time = as.POSIXct(c(NA, NA))
        ))
      }
      netfs:::.new_remote_info(character())
    },
    .package = "netfs"
  )
  expect_true(netfs:::.webdav_stat(con, "/a.txt")$exists)
  expect_equal(netfs:::.webdav_stat(con, "/a.txt")$type, "file")
  expect_equal(netfs:::.webdav_stat(con, "/sub")$type, "directory")
  expect_false(netfs:::.webdav_stat(con, "/nope.txt")$exists)
})

test_that("file_upload() only renames via copy+delete when the local and target basenames differ", {
  con <- webdav("https://host/")
  calls <- character()
  local_mocked_bindings(
    webdav_upload_file = function(...) { calls <<- c(calls, "upload"); TRUE },
    webdav_copy_file = function(...) { calls <<- c(calls, "copy"); TRUE },
    webdav_delete_resource = function(...) { calls <<- c(calls, "delete"); TRUE },
    .package = "webdav"
  )

  calls <- character()
  netfs:::.file_upload.netfs_webdav(con, "/local/report.csv", "/remote/report.csv")
  expect_equal(calls, "upload") # same basename: no rename needed

  calls <- character()
  netfs:::.file_upload.netfs_webdav(con, "/local/report.csv", "/remote/renamed.csv")
  expect_equal(calls, c("upload", "copy", "delete")) # different basename: rename follows
})

test_that("netfs_capabilities() reports WebDAV alongside the other backends", {
  all <- netfs_capabilities()
  expect_true("webdav" %in% all$backend)

  con <- webdav("https://host/")
  ops <- netfs_capabilities(con)
  expect_true(ops$supported[ops$operation == "file_copy"])
  expect_false(ops$supported[ops$operation == "file_chmod"])
  expect_false(ops$supported[ops$operation == "link_create"])
})
