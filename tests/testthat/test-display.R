flow_report <- function() {
  r <- create_report()
  add_line(r, "screened: ", record_count(r, "n_screened", 412))
  add_line(r, "excluded: ", record_count(r, "n_excluded", 3))
  record_unprinted_count(r, "~hidden", 7)
  r
}

test_that("show_count prints the masked value as text", {
  cohort_flow <- flow_report()
  expect_identical(show_count(cohort_flow, "n_screened"), "412")
  expect_identical(show_count(cohort_flow, "n_excluded"), "<5")
  expect_error(show_count(cohort_flow, "n_missing"), class = "dctools_display_error")
  expect_error(show_count(cohort_flow, "~hidden"), class = "dctools_display_error")
  expect_error(show_count(list(), "n_screened"), class = "dctools_display_error")
})

test_that("masking is recomputed, not taken from a resolver stored in the report", {
  cohort_flow <- flow_report()
  cohort_flow$resolver <- function(x) "999"
  expect_identical(show_count(cohort_flow, "n_excluded"), "<5")
})
