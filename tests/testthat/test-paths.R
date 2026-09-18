test_that("remote paths have a canonical representation", {
  expect_equal(netfs:::.netfs_path_normalize("///data//file.csv/"), "/data/file.csv")
  expect_equal(netfs:::.netfs_path_normalize(""), "/")
  expect_equal(
    netfs:::.netfs_path_normalize("DEMANDES_DONNEES"),
    netfs:::.netfs_path_normalize("/DEMANDES_DONNEES")
  )
  expect_equal(netfs:::.remote_path_join("/data", "a b"), "/data/a b")
  expect_equal(netfs:::.remote_path_basename("/data/a"), "a")
  expect_equal(netfs:::.remote_path_dirname("/data/a"), "/data")
  expect_error(netfs:::.netfs_path_normalize("/../secret"), class = "netfs_validation_error")
})

test_that("SMB paths convert to UNC without changing the share", {
  x <- smb("fileserver", "DATA")
  expect_equal(netfs:::.smb_to_unc(x, "/a/file.csv"), "\\\\fileserver\\DATA\\a\\file.csv")
})

test_that("directory detection dispatches locally or remotely", {
  local <- tempfile("netfs-dir-")
  dir.create(local)
  on.exit(unlink(local, recursive = TRUE), add = TRUE)
  expect_true(netfs:::.is_dir(local))

  local_mocked_bindings(
    .dir_exists = function(con, path, ...) identical(path, "/reports"),
    .package = "netfs"
  )
  expect_true(netfs:::.is_dir("reports", ssh("host")))
  expect_false(netfs:::.is_dir("missing", ssh("host")))
})

test_that("local name conflicts receive increasing numeric suffixes", {
  directory <- tempfile("netfs-names-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  original <- file.path(directory, "report.csv")
  first <- file.path(directory, "report-1.csv")
  file.create(original, first)

  expect_equal(
    netfs:::.next_available_local_path(original),
    file.path(directory, "report-2.csv")
  )
})
