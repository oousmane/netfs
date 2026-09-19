test_that("file_transfer stages data and preserves the source basename", {
  source_con <- ftp("ftp.example.org", user = "alice")
  destination_con <- smb("fileserver", "DATA", user = "alice")
  seen <- new.env(parent = emptyenv())

  local_mocked_bindings(
    .dir_exists = function(con, path, ...) FALSE,
    file_download = function(path, local, con, overwrite = FALSE, ...) {
      writeBin(charToRaw("payload"), local)
      seen$download_path <- path
      seen$staging_file <- local
      invisible(local)
    },
    file_upload = function(local, path, con, overwrite = FALSE, ...) {
      expect_true(file.exists(local))
      seen$upload_path <- path
      seen$overwrite <- overwrite
      invisible(path)
    },
    .package = "netfs"
  )

  result <- file_transfer(
    "/incoming/report.csv",
    "/archive/",
    from = source_con,
    to = destination_con,
    overwrite = TRUE
  )

  expect_equal(seen$download_path, "/incoming/report.csv")
  expect_equal(seen$upload_path, "/archive/report.csv")
  expect_true(seen$overwrite)
  expect_false(file.exists(seen$staging_file))
  expect_equal(result, fs::as_fs_path("/archive/report.csv"))
})

test_that("file_download and file_upload expand a `~` in `local`", {
  con <- smb("fileserver", "DATA")
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .dir_exists = function(con, path, ...) FALSE,
    .file_exists = function(con, path, ...) FALSE,
    .file_download = function(con, path, local, ...) { seen$download_local <- local; invisible(local) },
    .file_upload = function(con, local, path, ...) { seen$upload_local <- local; invisible(path) },
    .package = "netfs"
  )

  home_file <- fs::path_home("netfs-test-upload.csv")
  fs::file_create(home_file)
  on.exit(fs::file_delete(home_file), add = TRUE)

  file_download("/reports/report.csv", local = "~/report.csv", con = con)
  expect_false(grepl("^~", seen$download_local))
  expect_equal(as.character(seen$download_local), as.character(fs::path_expand("~/report.csv")))

  file_upload(local = "~/netfs-test-upload.csv", path = "/incoming/", con = con)
  expect_false(grepl("^~", seen$upload_local))
  expect_equal(as.character(seen$upload_local), as.character(fs::path_expand("~/netfs-test-upload.csv")))
})

test_that("file_transfer recognizes existing destination directories", {
  source_con <- ftp("ftp.example.org")
  destination_con <- smb("fileserver", "DATA")
  seen <- new.env(parent = emptyenv())

  local_mocked_bindings(
    .dir_exists = function(con, path, ...) identical(path, "/archive"),
    file_download = function(path, local, con, overwrite = FALSE, ...) {
      writeBin(charToRaw("payload"), local)
      invisible(local)
    },
    file_upload = function(local, path, con, overwrite = FALSE, ...) {
      seen$upload_path <- path
      invisible(path)
    },
    .package = "netfs"
  )

  file_transfer("/report.csv", "/archive", source_con, destination_con)
  expect_equal(seen$upload_path, "/archive/report.csv")
})
