test_that("capability outputs are stable tibbles", {
  all <- netfs_capabilities()
  expect_s3_class(all, "tbl_df")
  expect_named(all, c("backend", "available", "engine"))
  one <- netfs_capabilities(ssh("host"))
  expect_named(one, c("operation", "supported"))
  expect_false(one$supported[one$operation == "file_copy"])
})
