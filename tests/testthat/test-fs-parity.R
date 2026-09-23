# Fake a small two-level directory tree by mocking the internal generics
# directly (the same entry points every backend dispatches through), so
# these tests exercise the generic composition layer (recursion, dir_copy,
# file_create, is_*) independent of any one backend's own implementation.
.fake_tree <- function() {
  list(
    "/root" = c("/root/a.txt", "/root/sub"),
    "/root/sub" = c("/root/sub/b.txt")
  )
}

.fake_info <- function(path) {
  type <- if (identical(path, "/root/sub")) "directory" else "file"
  netfs:::.new_remote_info(path, type, if (type == "file") 10 else NA_real_, Sys.time())
}

local_fake_backend <- function(tree = .fake_tree(), .env = parent.frame()) {
  local_mocked_bindings(
    .dir_ls = function(con, path, ...) tree[[path]] %||% character(),
    .file_info = function(con, path, ...) .fake_info(path),
    .dir_info = function(con, path, ...) {
      entries <- tree[[path]] %||% character()
      if (!length(entries)) return(netfs:::.new_remote_info(character()))
      do.call(rbind, lapply(entries, .fake_info))
    },
    .dir_exists = function(con, path, ...) path %in% names(tree),
    .file_exists = function(con, path, ...) path %in% unlist(tree, use.names = FALSE) && !path %in% names(tree),
    .package = "netfs",
    .env = .env
  )
}

test_that("dir_ls(recurse = TRUE) walks nested subdirectories", {
  local_fake_backend()
  result <- dir_ls("/root", con = ssh("host"), recurse = TRUE)
  expect_setequal(as.character(result), c("/root/a.txt", "/root/sub", "/root/sub/b.txt"))
})

test_that("dir_ls(recurse = TRUE, type =) filters after the full walk", {
  local_fake_backend()
  result <- dir_ls("/root", con = ssh("host"), recurse = TRUE, type = "file")
  expect_setequal(as.character(result), c("/root/a.txt", "/root/sub/b.txt"))
})

test_that("dir_info(recurse = TRUE) returns one row per entry at every depth", {
  local_fake_backend()
  info <- dir_info("/root", con = ssh("host"), recurse = TRUE)
  expect_equal(nrow(info), 3L)
})

test_that("dir_map()/dir_walk() apply fun to every (optionally recursive) entry", {
  local_fake_backend()
  sizes <- dir_map("/root", con = ssh("host"), fun = nchar, recurse = TRUE)
  expect_length(sizes, 3L)

  seen <- character()
  dir_walk("/root", con = ssh("host"), fun = function(p) seen <<- c(seen, p), recurse = TRUE)
  expect_setequal(seen, c("/root/a.txt", "/root/sub", "/root/sub/b.txt"))
})

test_that("is_dir_empty()/is_file()/is_dir() read off the fake tree correctly", {
  local_fake_backend()
  con <- ssh("host")
  expect_false(is_dir_empty("/root", con = con))
  expect_true(is_file("/root/a.txt", con = con))
  expect_true(is_dir("/root/sub", con = con))
})

test_that("file_size() is a thin wrapper over file_info()$size", {
  local_fake_backend()
  expect_equal(as.numeric(file_size("/root/a.txt", con = ssh("host"))), 10)
})

test_that("is_link()/is_file_empty() return FALSE for a missing path instead of erroring", {
  local_mocked_bindings(
    .file_info = function(con, path, ...) abort_netfs_not_found("nope"),
    .package = "netfs"
  )
  con <- ssh("host")
  expect_false(is_link("/nope", con = con))
  expect_false(is_file_empty("/nope", con = con))
})

test_that("file_create() leaves an existing remote file untouched and uploads only when missing", {
  uploaded <- FALSE
  local_mocked_bindings(
    .file_exists = function(con, path, ...) identical(path, "/root/exists.txt"),
    .file_upload = function(con, local, path, ...) { uploaded <<- TRUE; path },
    .package = "netfs"
  )
  con <- ssh("host")
  file_create("/root/exists.txt", con = con)
  expect_false(uploaded)
  file_create("/root/missing.txt", con = con)
  expect_true(uploaded)
})

test_that("dir_copy() creates the destination tree and copies files through file_copy()", {
  local_fake_backend()
  created <- character(); copied <- list()
  local_mocked_bindings(
    .dir_exists = function(con, path, ...) identical(path, "/root"),
    .dir_create = function(con, path, ...) { created <<- c(created, path); path },
    .file_copy = function(con, path, new_path, ...) { copied[[path]] <<- new_path; new_path },
    .package = "netfs"
  )
  dir_copy("/root", "/dest", con = ssh("host"))
  expect_true("/dest" %in% created)
  expect_true("/dest/sub" %in% created)
  expect_equal(copied[["/root/a.txt"]], "/dest/a.txt")
  expect_equal(copied[["/root/sub/b.txt"]], "/dest/sub/b.txt")
})

test_that("dir_copy() falls back to download+upload staging when the backend has no native file_copy()", {
  # FTP has no copy command in the base protocol at all, so .file_copy
  # there always aborts netfs_unsupported. dir_copy() must still complete
  # the copy - just through a local temp file per entry - rather than
  # failing partway through with an empty directory skeleton left behind.
  local_fake_backend()
  created <- character(); downloaded <- list(); uploaded <- list()
  local_mocked_bindings(
    .dir_exists = function(con, path, ...) identical(path, "/root"),
    .dir_create = function(con, path, ...) { created <<- c(created, path); path },
    .file_copy = function(con, path, new_path, ...) abort_netfs_unsupported("no native copy", operation = "file_copy"),
    .file_download = function(con, path, local, ...) { downloaded[[path]] <<- local; invisible(local) },
    .file_upload = function(con, local, path, ...) { uploaded[[path]] <<- local; invisible(path) },
    .package = "netfs"
  )
  dir_copy("/root", "/dest", con = ftp("host"))
  expect_true("/dest" %in% created)
  expect_true("/dest/sub" %in% created)
  expect_equal(uploaded[["/dest/a.txt"]], downloaded[["/root/a.txt"]])
  expect_equal(uploaded[["/dest/sub/b.txt"]], downloaded[["/root/sub/b.txt"]])
})

test_that("file_show() is refused for any remote connection with a clear explanation", {
  expect_error(file_show("/root/a.txt", con = ssh("host")), class = "netfs_unsupported")
})

test_that("dir_delete(recurse = TRUE) removes every entry deepest-first before the directory itself", {
  # A plain rmdir/RMD only works on an already-empty directory (confirmed
  # live: "Directory not empty"). recurse = TRUE must delete every
  # descendant - files and subdirectories - before the directory that
  # contained them, or the final delete on the (still non-empty) top-level
  # directory fails the same way.
  local_fake_backend()
  deleted <- character()
  local_mocked_bindings(
    .file_delete = function(con, path, ...) { deleted <<- c(deleted, path); path },
    .dir_delete = function(con, path, ...) { deleted <<- c(deleted, path); path },
    .package = "netfs"
  )
  dir_delete("/root", con = ssh("host"), recurse = TRUE)
  expect_setequal(deleted, c("/root/a.txt", "/root/sub/b.txt", "/root/sub", "/root"))
  expect_equal(deleted[[length(deleted)]], "/root") # the directory itself always comes last
  expect_true(which(deleted == "/root/sub/b.txt") < which(deleted == "/root/sub")) # a child before its own parent
})

test_that("dir_delete() without recurse never walks the tree, matching its previous behavior", {
  local_fake_backend()
  walked <- FALSE
  local_mocked_bindings(
    .dir_info = function(con, path, ...) { walked <<- TRUE; netfs:::.new_remote_info(character()) },
    .dir_delete = function(con, path, ...) path,
    .package = "netfs"
  )
  dir_delete("/root", con = ssh("host"))
  expect_false(walked)
})

test_that("chmod/chown/touch/link operations default to a clear per-backend unsupported error", {
  ftp_con <- ftp("host")
  smb_con <- smb("host", "share")
  local_mocked_bindings(set_creds = function(...) invisible(NULL), .package = "smbclientr")

  expect_error(file_chmod("/x", con = ftp_con, mode = "644"), class = "netfs_unsupported")
  expect_error(file_chown("/x", con = smb_con, user_id = 1000), class = "netfs_unsupported")
  expect_error(file_touch("/x", con = ftp_con), class = "netfs_unsupported")
  expect_error(link_create("/target", "/x", con = smb_con), class = "netfs_unsupported")
  expect_error(link_path("/x", con = ftp_con), class = "netfs_unsupported")
  expect_error(link_delete("/x", con = smb_con), class = "netfs_unsupported")
  expect_error(file_access("/x", con = ftp_con, mode = "read"), class = "netfs_unsupported")
  # "exists" alone never needs the backend-specific generic, so it works
  # everywhere file_exists()/dir_exists() do.
  local_mocked_bindings(.file_exists = function(con, path, ...) TRUE, .dir_exists = function(con, path, ...) FALSE, .package = "netfs")
  expect_true(file_access("/x", con = ftp_con, mode = "exists"))
})
