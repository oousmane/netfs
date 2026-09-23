test_that("capability outputs are stable tibbles", {
  all <- netfs_capabilities()
  expect_s3_class(all, "tbl_df")
  expect_named(all, c("backend", "available", "engine"))
  one <- netfs_capabilities(ssh("host"))
  expect_named(one, c("operation", "supported"))
  expect_true(one$supported[one$operation == "file_copy"])
  expect_true(one$supported[one$operation == "dir_copy"])
  expect_true(one$supported[one$operation == "file_chmod"])

  ftp_ops <- netfs_capabilities(ftp("host"))
  expect_false(ftp_ops$supported[ftp_ops$operation == "file_copy"])
  expect_true(ftp_ops$supported[ftp_ops$operation == "dir_copy"]) # via local-staging fallback
  expect_false(ftp_ops$supported[ftp_ops$operation == "file_chmod"])
  expect_false(ftp_ops$supported[ftp_ops$operation == "link_create"])

  smb_ops <- netfs_capabilities(smb("host", "share"))
  expect_true(smb_ops$supported[smb_ops$operation == "file_copy"])
  expect_false(smb_ops$supported[smb_ops$operation == "file_chmod"])
})
