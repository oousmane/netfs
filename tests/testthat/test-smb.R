test_that("smb() builds a valid smbclientr connection with no duplicated fields", {
  local_mocked_bindings(set_creds = function(...) invisible(NULL), .package = "smbclientr")
  con <- smb("fileserver", "DATA", user = "alice", domain = "WORK")
  expect_true(inherits(con, "netfs_smb"))
  expect_true(inherits(con, "netfs_connection"))
  expect_true(inherits(con, "smb_connection")) # the smbclientr class, reused directly
  expect_equal(con$host, "fileserver")
  expect_equal(con$share, "DATA")
  expect_equal(con$user, "alice")
  expect_equal(con$domain, "WORK")
})

test_that("set_creds()/get_creds()/delete_creds() delegate to smbclientr for SMB connections", {
  con <- smb("fileserver", "DATA", user = "alice")
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    set_creds = function(con, password = NULL, keyring = NULL) { seen$set <- password; invisible(con) },
    get_creds = function(con, keyring = NULL) "secret",
    delete_creds = function(con, keyring = NULL) { seen$deleted <- TRUE; invisible(con) },
    .package = "smbclientr"
  )
  # Qualified deliberately: netfs and smbclientr both export set_creds()/
  # get_creds()/delete_creds() (smbclientr has its own, for standalone use),
  # and an unqualified call here can resolve to smbclientr's under some
  # test-execution contexts. netfs's own R code always calls
  # smbclientr::set_creds() etc. explicitly, so this only matters for
  # *calling code*, like this test, that isn't inside netfs's own namespace.
  netfs::set_creds(con, "secret")
  expect_equal(seen$set, "secret")
  expect_equal(format(netfs::get_creds(con)), "<hidden>") # still netfs's own hidden-display wrapper
  netfs::delete_creds(con)
  expect_true(seen$deleted)
})

test_that("each SMB adapter method delegates to the matching smbclientr function", {
  con <- smb("fileserver", "DATA")
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    dir_ls = function(path, con, type = "any", ...) { seen$dir_ls <- path; fs::as_fs_path("/data/a.txt") },
    dir_info = function(path, con, type = "any", ...) { seen$dir_info <- path; tibble::tibble(path = fs::as_fs_path("/data/a.txt"), type = factor("file")) },
    dir_exists = function(path, con) { seen$dir_exists <- path; c(x = TRUE) },
    dir_create = function(path, con, ...) { seen$dir_create <- path; fs::as_fs_path(path) },
    dir_delete = function(path, con) { seen$dir_delete <- path; fs::as_fs_path(path) },
    file_exists = function(path, con) { seen$file_exists <- path; c(x = FALSE) },
    file_delete = function(path, con) { seen$file_delete <- path; fs::as_fs_path(path) },
    file_copy = function(path, new_path, con, ...) { seen$file_copy <- c(path, new_path); fs::as_fs_path(new_path) },
    file_move = function(path, new_path, con) { seen$file_move <- c(path, new_path); fs::as_fs_path(new_path) },
    file_info = function(path, con, ...) { seen$file_info <- path; tibble::tibble(path = fs::as_fs_path(path), type = factor("file")) },
    file_download = function(path, local, con) { seen$download <- c(path, local); fs::as_fs_path(local) },
    file_upload = function(local, path, con) { seen$upload <- c(local, path); fs::as_fs_path(path) },
    .package = "smbclientr"
  )

  expect_equal(netfs:::.dir_ls.netfs_smb(con, "/data"), "/data/a.txt")
  expect_equal(seen$dir_ls, "/data")
  netfs:::.dir_info.netfs_smb(con, "/data"); expect_equal(seen$dir_info, "/data")
  netfs:::.dir_exists.netfs_smb(con, "/data"); expect_equal(seen$dir_exists, "/data")
  netfs:::.dir_create.netfs_smb(con, "/data"); expect_equal(seen$dir_create, "/data")
  netfs:::.dir_delete.netfs_smb(con, "/data"); expect_equal(seen$dir_delete, "/data")
  netfs:::.file_exists.netfs_smb(con, "/data/a.txt"); expect_equal(seen$file_exists, "/data/a.txt")
  netfs:::.file_delete.netfs_smb(con, "/data/a.txt"); expect_equal(seen$file_delete, "/data/a.txt")
  netfs:::.file_copy.netfs_smb(con, "/a.txt", "/b.txt"); expect_equal(seen$file_copy, c("/a.txt", "/b.txt"))
  netfs:::.file_move.netfs_smb(con, "/a.txt", "/b.txt"); expect_equal(seen$file_move, c("/a.txt", "/b.txt"))
  netfs:::.file_info.netfs_smb(con, "/data/a.txt"); expect_equal(seen$file_info, "/data/a.txt")
  netfs:::.file_download.netfs_smb(con, "/data/a.txt", "/tmp/a.txt"); expect_equal(seen$download, c("/data/a.txt", "/tmp/a.txt"))
  netfs:::.file_upload.netfs_smb(con, "/tmp/a.txt", "/data/a.txt"); expect_equal(seen$upload, c("/tmp/a.txt", "/data/a.txt"))
})

test_that("smbclientr conditions are translated to netfs's own condition classes", {
  con <- smb("fileserver", "DATA")
  cases <- list(
    list(smbclientr_class = "smbclientr_not_found", netfs_class = "netfs_not_found"),
    list(smbclientr_class = "smbclientr_auth_error", netfs_class = "netfs_auth_error"),
    list(smbclientr_class = "smbclientr_permission_error", netfs_class = "netfs_permission_error"),
    list(smbclientr_class = "smbclientr_timeout", netfs_class = "netfs_timeout"),
    list(smbclientr_class = "smbclientr_backend_unavailable", netfs_class = "netfs_backend_unavailable"),
    list(smbclientr_class = "smbclientr_unsupported", netfs_class = "netfs_unsupported"),
    list(smbclientr_class = "smbclientr_destination_exists", netfs_class = "netfs_destination_exists"),
    list(smbclientr_class = "smbclientr_connection_error", netfs_class = "netfs_connection_error")
  )
  for (case in cases) {
    local_mocked_bindings(
      dir_ls = function(...) rlang::abort("boom", class = c(case$smbclientr_class, "smbclientr_error")),
      .package = "smbclientr"
    )
    expect_error(netfs:::.dir_ls.netfs_smb(con, "/data"), class = case$netfs_class)
  }
})
