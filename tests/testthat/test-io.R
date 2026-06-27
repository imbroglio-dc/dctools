test_that("suppress_small_cells masks counts in 1:(threshold-1)", {
  tab <- data.frame(group = c("a", "b", "c"), n = c(3, 42, 0))
  out <- suppress_small_cells(tab, cols = "n")
  expect_equal(out$n, c("<11", "42", "0")) # 3 masked, 42 kept, 0 untouched
})

test_that("suppress_small_cells can also mask zeros", {
  tab <- data.frame(n = c(0, 5, 20))
  out <- suppress_small_cells(tab, cols = "n", mask_zero = TRUE)
  expect_equal(out$n, c("<11", "<11", "20"))
})

test_that("suppress_small_cells defaults to numeric columns", {
  tab <- data.frame(group = c("a", "b"), n = c(2, 50), pct = c(4, 96))
  out <- suppress_small_cells(tab)
  expect_equal(out$n, c("<11", "50"))
  expect_equal(out$pct, c("<11", "96"))
  expect_type(out$group, "character")
})
