test_that("ssh_keygen() generates a key with the expected arguments and prints the copy-id command", {
  path <- tempfile("netfs-key-")
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .run_command = function(command, args, ...) {
      seen$command <- command
      seen$args <- args
      fs::file_create(args[[length(args)]]) # the `-f <path>` value, as real ssh-keygen would
      list(status = 0L, stdout = "", stderr = "")
    },
    .package = "netfs"
  )

  messages <- testthat::capture_messages(result <- ssh_keygen("host.example.org", user = "alice", path = path))
  expect_equal(result, fs::path_expand(path))
  expect_equal(seen$command, "ssh-keygen")
  expect_equal(seen$args, c("-q", "-t", "ed25519", "-N", "", "-C", "netfs-alice_host.example.org", "-f", result))
  expect_match(paste(messages, collapse = ""), "Generated identity file")
  expect_match(paste(messages, collapse = ""), "ssh-copy-id -i .*\\.pub alice@host\\.example\\.org", perl = TRUE)
})

test_that("ssh_keygen() reuses an existing key unless overwrite = TRUE", {
  path <- tempfile("netfs-key-")
  fs::file_create(path)
  called <- FALSE
  local_mocked_bindings(
    .run_command = function(...) { called <<- TRUE; list(status = 0L, stdout = "", stderr = "") },
    .package = "netfs"
  )

  messages <- testthat::capture_messages(ssh_keygen("host", path = path))
  expect_match(paste(messages, collapse = ""), "Using existing identity file")
  expect_false(called)

  messages <- testthat::capture_messages(ssh_keygen("host", path = path, overwrite = TRUE))
  expect_match(paste(messages, collapse = ""), "Generated identity file")
  expect_true(called)
})

test_that("a non-default port is included in the suggested ssh-copy-id command", {
  path <- tempfile("netfs-key-")
  local_mocked_bindings(
    .run_command = function(command, args, ...) {
      fs::file_create(args[[length(args)]])
      list(status = 0L, stdout = "", stderr = "")
    },
    .package = "netfs"
  )
  messages <- testthat::capture_messages(ssh_keygen("host", user = "bob", port = 2222, path = path))
  expect_match(paste(messages, collapse = ""), "ssh-copy-id -i .*\\.pub -p 2222 bob@host", perl = TRUE)
})

test_that("ssh_keygen() surfaces a structured error when ssh-keygen is unavailable", {
  local_mocked_bindings(Sys.which = function(...) "", .package = "base")
  expect_error(ssh_keygen("host"), class = "netfs_backend_unavailable")
})

test_that("a failed ssh-keygen invocation surfaces its own stderr", {
  path <- tempfile("netfs-key-")
  local_mocked_bindings(
    .run_command = function(...) list(status = 1L, stdout = "", stderr = "ssh-keygen: could not create directory"),
    .package = "netfs"
  )
  expect_error(ssh_keygen("host", path = path), "could not create directory", class = "netfs_backend_error")
})
