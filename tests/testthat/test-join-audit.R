test_that("join_audit performs the join and attaches an audit trail", {
  left <- data.frame(id = 1:3, x = c("a", "b", "c"))
  right <- data.frame(id = 1:3, y = c(10, 20, 30))
  res <- suppressMessages(join_audit(left, right, by = "id"))
  expect_true("y" %in% names(res))
  expect_equal(nrow(res), 3L)
  a <- attr(res, "join_audit")
  expect_equal(a$left_n, 3L)
  expect_equal(a$right_n, 3L)
  expect_equal(a$joined_n, 3L)
  expect_equal(a$match_rate, 1)
  expect_equal(a$unmatched_left, 0L)
})

test_that("join_audit reports a match rate below 100% for partial matches", {
  left <- data.frame(id = 1:3, x = 1:3)
  right <- data.frame(id = 1:2, y = c(10, 20))
  res <- suppressMessages(join_audit(left, right, by = "id"))
  a <- attr(res, "join_audit")
  expect_equal(a$matched_left, 2L)
  expect_equal(a$unmatched_left, 1L)
  expect_equal(a$match_rate, 2 / 3, tolerance = 1e-9)
})

test_that("join_audit warns on row inflation from duplicate right keys", {
  left <- data.frame(id = c(1, 2), x = c("a", "b"))
  right <- data.frame(id = c(1, 1, 2), y = c(10, 11, 20)) # key 1 duplicated
  expect_warning(res <- join_audit(left, right, by = "id"), "inflat|grew|duplicate")
  a <- attr(res, "join_audit")
  expect_equal(a$joined_n, 3L)
  expect_true(a$joined_n > a$left_n)
})

test_that("join_audit enforces a declared relationship via dplyr", {
  left <- data.frame(id = c(1, 2), x = c("a", "b"))
  right <- data.frame(id = c(1, 1, 2), y = c(10, 11, 20))
  expect_error(
    join_audit(left, right, by = "id", relationship = "one-to-one")
  )
})

test_that("join_audit defaults na_matches to 'never'", {
  left <- data.frame(id = c(1, NA), x = c("a", "b"))
  right <- data.frame(id = c(1, NA), y = c(10, 99))
  res <- suppressMessages(join_audit(left, right, by = "id"))
  a <- attr(res, "join_audit")
  # NA key on the left must NOT match the NA key on the right
  expect_equal(a$matched_left, 1L)
  expect_equal(a$unmatched_left, 1L)
})

test_that("join_audit supports an inner join that drops unmatched left rows", {
  left <- data.frame(id = 1:3, x = 1:3)
  right <- data.frame(id = 1:2, y = c(10, 20))
  res <- suppressMessages(join_audit(left, right, by = "id", type = "inner"))
  expect_equal(nrow(res), 2L)
  expect_equal(attr(res, "join_audit")$joined_n, 2L)
})

test_that("join_audit errors on a missing key column", {
  left <- data.frame(id = 1:3, x = 1:3)
  right <- data.frame(id = 1:3, y = 1:3)
  expect_error(join_audit(left, right, by = "patient_id"), "patient_id")
})
