test_that("credential services are stable and connection-specific", {
  expect_equal(
    netfs:::.credential_service(ssh("server.example.org", user = "alice")),
    "netfs:ssh:server.example.org:22"
  )
  expect_equal(
    netfs:::.credential_service(smb("fileserver", "DATA", user = "alice")),
    "netfs:smb:fileserver/DATA"
  )
})

test_that("credential helpers delegate to keyring without storing secrets", {
  stored <- new.env(parent = emptyenv())
  local_mocked_bindings(
    .keyring_set_with_value = function(service, username, password, keyring) {
      stored$service <- service
      stored$username <- username
      stored$password <- password
      stored$keyring <- keyring
    },
    .keyring_get = function(service, username, keyring) "secret",
    .keyring_delete = function(service, username, keyring) invisible(NULL),
    .package = "netfs"
  )

  con <- ftp("ftp.example.org", user = "alice")
  expect_invisible(set_creds(con, "secret"))
  expect_equal(stored$service, "netfs:ftp:ftp.example.org:21")
  expect_equal(stored$username, "alice")
  credential <- get_creds(con)
  expect_s3_class(credential, "netfs_creds")
  printed <- capture.output(print(credential))
  expect_true(any(grepl("<hidden>", printed, fixed = TRUE)))
  expect_false(any(grepl("secret", printed, fixed = TRUE)))
  expect_output(str(credential), "<hidden>", fixed = TRUE)
  expect_equal(format(credential), "<hidden>")
  expect_invisible(delete_creds(con))
  expect_null(con$password)
})

test_that("NETFS_KEYRING selects a named keyring", {
  old <- Sys.getenv("NETFS_KEYRING", unset = NA_character_)
  on.exit({
    if (is.na(old)) {
      Sys.unsetenv("NETFS_KEYRING")
    } else {
      Sys.setenv(NETFS_KEYRING = old)
    }
  }, add = TRUE)
  Sys.setenv(NETFS_KEYRING = "netfs-test")
  expect_equal(netfs:::.netfs_keyring(), "netfs-test")
})
