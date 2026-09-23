test_that("condition constructors have stable classes", {
  expect_error(netfs:::abort_netfs_not_found("missing"), class = "netfs_not_found")
  expect_error(netfs:::abort_netfs_unsupported("unsupported"), class = "netfs_unsupported")
})

test_that("unsupported remote copies fail explicitly", {
  # FTP has no copy command in the base protocol; SSH has its own shell (cp)
  # and is no longer in this category.
  expect_error(file_copy("/a", "/b", con = ftp("host")), class = "netfs_unsupported")
})

test_that("transfers require a remote connection", {
  expect_error(
    file_download("/remote/file", local = tempfile()),
    "`con` is required",
    class = "netfs_validation_error"
  )
  expect_error(
    file_upload(tempfile(), "/remote/file"),
    "`con` is required",
    class = "netfs_validation_error"
  )
})

test_that("upload directory destinations append the local basename", {
  source <- tempfile(fileext = ".pdf")
  writeBin(charToRaw("test"), source)
  on.exit(unlink(source), add = TRUE)
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .dir_exists = function(con, path, ...) FALSE,
    .file_exists = function(con, path, ...) FALSE,
    .file_upload = function(con, local, path, ...) {
      seen$path <- path
      invisible(path)
    },
    .package = "netfs"
  )

  file_upload(source, "/BAD-netfs/", con = ssh("host"))
  expect_equal(seen$path, paste0("/BAD-netfs/", basename(source)))
})

test_that("download directory destinations append the remote basename", {
  destination <- tempfile("netfs-download-")
  dir.create(destination)
  on.exit(unlink(destination, recursive = TRUE), add = TRUE)
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .file_download = function(con, path, local, ...) {
      seen$local <- local
      invisible(local)
    },
    .package = "netfs"
  )

  file_download("/reports/nakoulma.xls", local = destination, con = ssh("host"))
  expect_equal(seen$local, fs::path(destination, "nakoulma.xls"))
})

test_that("existing remote directories append the local basename", {
  source <- tempfile(fileext = ".pdf")
  writeBin(charToRaw("test"), source)
  on.exit(unlink(source), add = TRUE)
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .dir_exists = function(con, path, ...) identical(path, "/BAD-netfs"),
    .file_exists = function(con, path, ...) FALSE,
    .file_upload = function(con, local, path, ...) {
      seen$path <- path
      invisible(path)
    },
    .package = "netfs"
  )

  file_upload(source, "/BAD-netfs", con = ssh("host"))
  expect_equal(seen$path, paste0("/BAD-netfs/", basename(source)))
})

test_that("downloads preserve existing files with a numbered name", {
  directory <- tempfile("netfs-download-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  destination <- file.path(directory, "report.csv")
  file.create(destination)
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .file_download = function(con, path, local, ...) {
      seen$local <- local
      invisible(local)
    },
    .package = "netfs"
  )

  result <- file_download("/reports/report.csv", destination, ssh("host"))
  expect_equal(as.character(seen$local), as.character(fs::path_expand(file.path(directory, "report-1.csv"))))
  expect_equal(result, fs::as_fs_path(fs::path_abs(fs::path_expand(file.path(directory, "report-1.csv")))))
})
