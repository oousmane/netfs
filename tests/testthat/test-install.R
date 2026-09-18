test_that("installation plans use platform package names", {
  debian <- netfs:::.smbclient_install_plan("linux", "apt-get")
  expect_equal(debian[[2L]]$args, c("install", "-y", "smbclient"))

  fedora <- netfs:::.smbclient_install_plan("linux", "dnf")
  expect_equal(fedora[[1L]]$args, c("install", "-y", "samba-client"))

  arch <- netfs:::.smbclient_install_plan("linux", "pacman")
  expect_true("smbclient" %in% arch[[1L]]$args)

  macos <- netfs:::.smbclient_install_plan("darwin", "brew")
  expect_equal(macos[[1L]]$args, c("install", "samba"))
  expect_match(
    netfs:::.format_install_step(debian[[1L]], elevated = TRUE),
    "^sudo -n apt-get"
  )
})

test_that("dry runs never execute installation commands", {
  skip_on_os("windows")
  local_mocked_bindings(
    .has_smbclient = function() FALSE,
    .smbclient_install_plan = function(...) list(
      list(command = "apt-get", args = c("install", "-y", "smbclient"))
    ),
    .run_install_step = function(...) fail("installation command was executed"),
    .package = "netfs"
  )
  expect_message(plan <- install_smbclient(dry_run = TRUE), "smbclient")
  expect_type(plan, "list")
})

test_that("non-interactive installation requires explicit authorization", {
  skip_on_os("windows")
  skip_if(interactive())
  local_mocked_bindings(
    .has_smbclient = function() FALSE,
    .smbclient_install_plan = function(...) list(
      list(command = "apt-get", args = c("install", "-y", "smbclient"))
    ),
    .package = "netfs"
  )
  expect_error(
    install_smbclient(),
    class = "netfs_install_confirmation_required"
  )
})

test_that("installation steps use bounded non-interactive processx runs", {
  seen <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .processx_run = function(...) {
      seen$call <- list(...)
      list(status = 0L, stdout = "installed", stderr = "", timeout = FALSE)
    },
    .package = "netfs"
  )

  result <- netfs:::.run_install_step(
    list(command = "apt-get", args = c("install", "-y", "smbclient")),
    elevated = TRUE,
    timeout = 12
  )

  expect_equal(seen$call[[1L]], "sudo")
  expect_equal(
    seen$call$args,
    c("-n", "apt-get", "install", "-y", "smbclient")
  )
  expect_equal(seen$call$timeout, 12)
  expect_equal(seen$call$stdin, "")
  expect_true(seen$call$cleanup_tree)
  expect_equal(result$status, 0L)
})

test_that("installation timeouts raise a typed error", {
  local_mocked_bindings(
    .processx_run = function(...) {
      list(status = 0L, stdout = "", stderr = "", timeout = TRUE)
    },
    .package = "netfs"
  )

  expect_error(
    netfs:::.run_install_step(
      list(command = "apt-get", args = "update"),
      timeout = 1
    ),
    class = "netfs_timeout"
  )
})

test_that("installation timeout must be finite", {
  expect_error(
    install_smbclient(timeout = Inf),
    class = "netfs_validation_error"
  )
})
