test_that("assert_columns passes through and errors on missing", {
  df <- data.frame(id = 1:3, age = c(40, 50, 60))
  expect_identical(assert_columns(df, c("id", "age")), df)
  expect_error(assert_columns(df, c("id", "weight")), "weight")
})

test_that("check_unique_id detects duplicate keys", {
  df <- data.frame(id = c(1, 1, 2), x = 1:3)
  expect_error(check_unique_id(df, "id"))
  dupes <- suppressWarnings(check_unique_id(df, "id", error = FALSE))
  expect_equal(nrow(dupes), 1L)
})

test_that("check_unique_id is silent for a unique key", {
  df <- data.frame(id = 1:3, x = 1:3)
  expect_silent(check_unique_id(df, "id"))
  expect_equal(nrow(check_unique_id(df, "id")), 0L)
})

test_that("flag_out_of_range finds out-of-range values and ignores NA", {
  res <- suppressWarnings(flag_out_of_range(c(5, 200, NA, -1), lo = 0, hi = 100))
  expect_equal(res$index, c(2L, 4L))
  expect_equal(res$value, c(200, -1))
})
