test_that("read_packages strips comments and blanks, de-duplicates", {
  tmp <- withr::local_tempfile()
  writeLines(
    c("dplyr", "  # a comment", "", "ggplot2  // trailing", "dplyr", "  tidyr "),
    tmp
  )
  expect_equal(read_packages(tmp), c("dplyr", "ggplot2", "tidyr"))
})

test_that("read_packages handles an empty file", {
  tmp <- withr::local_tempfile()
  file.create(tmp)
  expect_equal(read_packages(tmp), character(0))
})
