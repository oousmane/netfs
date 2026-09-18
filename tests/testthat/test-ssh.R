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
  expect_equal(dir_ls("/data", con = ssh("host")), c("/data/a b", "/data/c"))
})
