test_that("SSH targets and arguments are constructed safely", {
  x <- ssh("host", user = "alice", port = 2200, identity_file = "key file")
  expect_equal(netfs:::.ssh_target(x), "alice@host")
  expect_true(all(c("2200", "key file") %in% netfs:::.ssh_common_args(x)))
})

test_that("SSH listing parsing handles spaces", {
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) list(status = 0L, stdout = "/data/a b\n/data/c\n", stderr = ""),
    .package = "netfs"
  )
  expect_equal(dir_ls("/data", con = ssh("host")), fs::as_fs_path(c("/data/a b", "/data/c")))
})

test_that("file_info() falls back to BSD stat syntax for non-Linux remotes", {
  # `stat -c` is GNU-coreutils-specific; confirmed locally that macOS's
  # BSD stat errors on it ("illegal option -- c"). The script must try
  # both, since netfs doesn't know the remote OS in advance.
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .ssh_run = function(con, script, ...) { seen$script <- script; list(status = 0L, stdout = "Regular File\t213\t1755321821\n", stderr = "") },
    .package = "netfs"
  )
  info <- netfs:::.file_info.netfs_ssh(ssh("host"), "/etc/hosts")
  expect_match(seen$script, "stat -c ", fixed = TRUE)
  expect_match(seen$script, "stat -f ", fixed = TRUE)
  expect_equal(as.character(info$type), "file")
  expect_equal(as.numeric(info$size), 213)
})
