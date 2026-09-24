test_that("s3() requires a bucket and stores credential fields without eagerly building a client", {
  con <- s3("my-bucket", aws_access_key_id = "AKIA...", region_name = "us-east-1")
  expect_true(inherits(con, "netfs_s3"))
  expect_equal(con$bucket, "my-bucket")
  expect_equal(con$user, "AKIA...")
  expect_error(s3(bucket = 123), class = "netfs_validation_error")
})

test_that("path helpers convert between netfs paths and s3fs's bucket/key and s3:// conventions", {
  con <- list(bucket = "my-bucket")
  expect_equal(netfs:::.s3_path(con, "/"), "my-bucket")
  expect_equal(netfs:::.s3_path(con, "/reports/a.txt"), "my-bucket/reports/a.txt")
  expect_equal(netfs:::.s3_uri(con, "/reports/a.txt"), "s3://my-bucket/reports/a.txt")
  expect_equal(netfs:::.s3_to_netfs_path(con, "reports/a.txt"), "/reports/a.txt")
  expect_equal(netfs:::.s3_to_netfs_path(con, "my-bucket/reports/a.txt"), "/reports/a.txt")
  expect_equal(netfs:::.s3_to_netfs_path(con, "s3://my-bucket/reports/"), "/reports")
})

test_that(".s3_run() translates a failure correctly even though s3fs's future.apply-based methods re-enter the handler stack on error", {
  # Confirmed live: file_info() (which uses future_lapply internally)
  # leaves handler-stack state active during its own error cleanup, so a
  # condition thrown from *inside* a tryCatch handler here was getting
  # re-caught by that same tryCatch's generic error= handler instead of
  # reaching the caller - collapsing every classified error (not_found,
  # permission, auth) down to a generic netfs_backend_error. Reproduced
  # with a fake condition carrying future.apply's exact class shape.
  con <- list(bucket = "my-bucket")
  fake_error <- function(classes) {
    structure(class = c(classes, "error", "condition"), list(message = "boom", call = NULL))
  }
  throw <- function(classes) stop(fake_error(classes))

  expect_error(netfs:::.s3_run(con, throw(c("paws_error", "http_404", "http_400", "http_error"))), class = "netfs_not_found")
  expect_error(netfs:::.s3_run(con, throw(c("paws_error", "http_403", "http_400", "http_error"))), class = "netfs_permission_error")
  expect_error(netfs:::.s3_run(con, throw(c("paws_error", "http_401", "http_400", "http_error"))), class = "netfs_auth_error")
  expect_error(netfs:::.s3_run(con, throw("some_other_error")), class = "netfs_backend_error")

  expect_equal(netfs:::.s3_run(con, 42), 42) # a real success value must pass through unchanged
})

test_that("file_copy()/file_move() build s3:// URIs, since s3fs's own dispatch silently no-ops on a bare bucket/key string", {
  con <- s3("my-bucket")
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .s3_client = function(con) list(
      file_copy = function(path, new_path, ...) { seen$copy <- c(path, new_path); TRUE },
      file_move = function(path, new_path, ...) { seen$move <- c(path, new_path); TRUE }
    ),
    .package = "netfs"
  )
  netfs:::.file_copy.netfs_s3(con, "/a.txt", "/b.txt")
  expect_equal(seen$copy, c("s3://my-bucket/a.txt", "s3://my-bucket/b.txt"))
  netfs:::.file_move.netfs_s3(con, "/a.txt", "/b.txt")
  expect_equal(seen$move, c("s3://my-bucket/a.txt", "s3://my-bucket/b.txt"))
})

test_that("dir_delete() without recurse refuses a non-empty S3 prefix, since S3 has no native equivalent of a plain rmdir", {
  con <- s3("my-bucket")
  local_mocked_bindings(
    .s3_client = function(con) list(
      dir_info = function(path, recurse = FALSE, ...) {
        tibble::tibble(key = "sub/a.txt", type = "file", size = 1, last_modified = Sys.time())
      }
    ),
    .package = "netfs"
  )
  expect_error(netfs:::.dir_delete.netfs_s3(con, "/sub"), "not empty")
})

test_that("netfs_capabilities() reports S3 alongside the other backends", {
  all <- netfs_capabilities()
  expect_true("s3" %in% all$backend)

  con <- s3("my-bucket")
  ops <- netfs_capabilities(con)
  expect_true(ops$supported[ops$operation == "file_copy"])
  expect_false(ops$supported[ops$operation == "file_chmod"])
  expect_false(ops$supported[ops$operation == "link_create"])
})
