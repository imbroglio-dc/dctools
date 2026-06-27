test_that("detect_missing_sentinels finds numeric codes and string tokens", {
  df <- data.frame(
    age = c(40, 50, -9, 60),
    sex = c("M", "F", "unknown", "  "),
    stringsAsFactors = FALSE
  )
  rep <- detect_missing_sentinels(df)
  expect_true(any(rep$column == "age" & rep$sentinel == "-9"))
  expect_true(any(rep$column == "sex" & rep$sentinel == "unknown"))
  # whitespace-only matches the "" token after trimming
  expect_true(any(rep$column == "sex" & rep$sentinel == ""))
})

test_that("detect_missing_sentinels returns empty report when clean", {
  df <- data.frame(x = 1:3, y = c("a", "b", "c"), stringsAsFactors = FALSE)
  expect_equal(nrow(detect_missing_sentinels(df)), 0L)
})

test_that("check_colnames flags duplicates, spaces, case-collisions", {
  df <- data.frame(1, 2, 3, 4)
  names(df) <- c("Age", "age", "bad name", "ok")
  res <- check_colnames(df)
  expect_true("Age" %in% res$column)
  expect_true(any(grepl("case-collision", res$issues)))
  expect_true(any(res$column == "bad name" & grepl("whitespace", res$issues)))
})

test_that("clean_colnames produces unique snake_case and records a map", {
  df <- data.frame(1, 2, 3)
  names(df) <- c("Patient ID", "patientID", "WBC (k/uL)")
  out <- clean_colnames(df)
  expect_false(any(duplicated(names(out))))
  expect_true(all(grepl("^[a-z0-9_]+$", names(out))))
  expect_s3_class(attr(out, "colname_map"), "data.frame")
})

test_that("check_types flags numeric-as-text and binary-as-numeric", {
  df <- data.frame(
    num_txt = c("1,000", "2,500", "3"),
    flag = c(0, 1, 1),
    stringsAsFactors = FALSE
  )
  res <- check_types(df)
  expect_true(any(res$column == "num_txt" & res$issue == "numeric stored as text"))
  expect_true(any(res$column == "flag" & res$issue == "binary stored as numeric"))
})

test_that("check_constant_cols finds constant and all-NA columns", {
  df <- data.frame(a = c(1, 1, 1), b = c(NA, NA, NA), c = c(1, 2, 3))
  res <- check_constant_cols(df)
  expect_true(any(res$column == "a" & res$issue == "constant"))
  expect_true(any(res$column == "b" & res$issue == "all missing"))
  expect_false("c" %in% res$column)
})

test_that("check_collinearity returns highly correlated pairs, sorted", {
  set.seed(1)
  x <- rnorm(100)
  df <- data.frame(x = x, x_copy = x + rnorm(100, sd = 1e-6), z = rnorm(100))
  res <- check_collinearity(df, threshold = 0.9)
  expect_true(nrow(res) >= 1L)
  expect_true(all(c("x", "x_copy") %in% c(res$col1, res$col2)))
  expect_equal(nrow(check_collinearity(data.frame(only = 1:3))), 0L)
})

test_that("describe_cohort bundles overview and screens", {
  df <- data.frame(a = c(1, 1, NA), b = c("x", "y", "z"), stringsAsFactors = FALSE)
  d <- describe_cohort(df)
  expect_named(
    d,
    c("dims", "overview", "colname_issues", "type_issues",
      "constant_cols", "missing_sentinels", "collinearity")
  )
  expect_equal(unname(d$dims[["rows"]]), 3L)
  expect_equal(nrow(d$overview), 2L)
})
