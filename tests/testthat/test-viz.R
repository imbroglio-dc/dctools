test_that("theme_dc returns a ggplot2 theme", {
  th <- theme_dc()
  expect_s3_class(th, "theme")
  expect_s3_class(th, "gg")
})

test_that("theme_dc respects base_size", {
  expect_no_error(theme_dc(base_size = 14))
})
