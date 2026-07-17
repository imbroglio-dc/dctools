test_that("compare_targets passes matches within tolerance, by kind", {
  targets <- data.frame(
    target = c("att", "N"), value = c(-1.632, 2847),
    kind = c("estimate", "count")
  )
  results <- data.frame(target = c("att", "N"), value = c(-1.628, 2847))
  res <- suppressMessages(compare_targets(results, targets))
  expect_equal(res$status, c("PASS", "PASS"))
  expect_equal(res$diff[1], 0.004, tolerance = 1e-9)
  expect_equal(res$tolerance[1], 0.01)
})

test_that("compare_targets fails an estimate outside tolerance", {
  targets <- data.frame(target = "att", value = -1.632, kind = "estimate")
  results <- data.frame(target = "att", value = -1.50)
  res <- suppressWarnings(compare_targets(results, targets))
  expect_equal(res$status, "FAIL")
})

test_that("compare_targets marks an unmatched target, never a silent pass", {
  targets <- data.frame(
    target = c("att", "extra"), value = c(-1.6, 3),
    kind = c("estimate", "count")
  )
  results <- data.frame(target = "att", value = -1.6)
  res <- suppressWarnings(compare_targets(results, targets))
  expect_equal(res$status[res$target == "extra"], "UNMATCHED")
  expect_true(is.na(res$computed[res$target == "extra"]))
})

test_that("compare_targets honors a per-row tolerance override column", {
  targets <- data.frame(
    target = "att", value = 1.0, kind = "estimate", tolerance = 0.5
  )
  results <- data.frame(target = "att", value = 1.3) # .3 > .01 default, < .5
  res <- suppressMessages(compare_targets(results, targets))
  expect_equal(res$status, "PASS")
  expect_equal(res$tolerance, 0.5)
})

test_that("compare_targets matches p-values by significance level", {
  targets <- data.frame(
    target = c("p_same", "p_diff"), value = c(0.003, 0.02),
    kind = c("p_value", "p_value")
  )
  results <- data.frame(target = c("p_same", "p_diff"), value = c(0.007, 0.2))
  res <- suppressWarnings(compare_targets(results, targets))
  expect_equal(res$status[res$target == "p_same"], "PASS")
  expect_equal(res$status[res$target == "p_diff"], "FAIL")
  expect_true(is.na(res$diff[res$target == "p_same"]))
})

test_that("compare_targets accepts a named numeric vector of results", {
  targets <- data.frame(
    target = c("att", "N"), value = c(-1.632, 2847),
    kind = c("estimate", "count")
  )
  res <- suppressMessages(compare_targets(c(att = -1.628, N = 2847), targets))
  expect_equal(res$status, c("PASS", "PASS"))
})

test_that("compare_targets errors on an unknown kind with no tolerance", {
  targets <- data.frame(target = "x", value = 1, kind = "mystery")
  results <- data.frame(target = "x", value = 1.2)
  expect_error(suppressWarnings(compare_targets(results, targets)), "tolerance")
})

test_that("compare_targets errors on missing required columns", {
  targets <- data.frame(target = "x", value = 1) # no kind
  results <- data.frame(target = "x", value = 1)
  expect_error(compare_targets(results, targets), "kind")
})
