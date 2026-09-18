test_that("installation plans use platform package names", {
  debian <- netfs:::.smbclient_install_plan("linux", "apt-get")
  expect_equal(debian[[2L]]$args, c("install", "-y", "smbclient"))

  fedora <- netfs:::.smbclient_install_plan("linux", "dnf")
  expect_equal(fedora[[1L]]$args, c("install", "-y", "samba-client"))

  arch <- netfs:::.smbclient_install_plan("linux", "pacman")
  expect_true("smbclient" %in% arch[[1L]]$args)

  macos <- netfs:::.smbclient_install_plan("darwin", "brew")
  expect_equal(macos[[1L]]$args, c("install", "samba"))
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
