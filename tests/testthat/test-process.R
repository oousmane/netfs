test_that("missing executables produce structured errors", {
  command <- paste0("netfs-command-that-does-not-exist-", Sys.getpid())
  expect_error(netfs:::.run_command(command), class = "netfs_backend_unavailable")
})

test_that("redaction removes secrets", {
  expect_equal(netfs:::.redact_text("token=abc", "abc"), "token=<redacted>")
})

test_that("non-zero status is preserved", {
  rscript <- file.path(R.home("bin"), "Rscript")
  result <- netfs:::.run_command(rscript, c("-e", "quit(status = 7)"))
  expect_equal(result$status, 7)
})

test_that("timeouts produce structured errors", {
  rscript <- file.path(R.home("bin"), "Rscript")
  expect_error(
    netfs:::.run_command(rscript, c("-e", "Sys.sleep(2)"), timeout = 0.05),
    class = "netfs_timeout"
  )
})

test_that("an error while lazily constructing args is not misreported as a failed execution", {
  rscript <- file.path(R.home("bin"), "Rscript")
  # `args` is passed as an unevaluated expression, exactly like the
  # sprintf(...)/.smb_path(path) chain callers build for `command` in
  # .smb_run() — it must only be forced (and any error from it surfaced
  # under its own class) outside the process-execution tryCatch.
  expect_error(
    netfs:::.run_command(rscript, netfs:::.check_scalar_character(c("a", "b"), "path")),
    class = "netfs_validation_error"
  )
})
