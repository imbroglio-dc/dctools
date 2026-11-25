flow_report <- function() {
  r <- create_report()
  add_line(r, "screened: ", record_count(r, "n_screened", 412))
  add_line(r, "excluded: ", record_count(r, "n_excluded", 3))
  record_unprinted_count(r, "~hidden", 7)
  r
}

page <- function(...) {
  c(
    "<!DOCTYPE html>",
    "<html><head><title>Flow 2026</title><style>.a { width: 300px; }</style>",
    "<script>var x = 12345;</script></head><body>",
    "<h1>Cohort flow</h1>",
    ...,
    "</body></html>"
  )
}

write_page <- function(lines) {
  path <- withr::local_tempfile(fileext = ".html", .local_envir = parent.frame())
  writeLines(lines, path)
  path
}

test_that("show_count prints the masked value, in a span naming target, id and rule", {
  cohort_flow <- flow_report()
  expect_identical(
    as.character(show_count(cohort_flow, "n_screened", format = "html")),
    "<span class=\"dctools-value\" data-target=\"cohort_flow\" data-id=\"n_screened\" data-rule=\"count\">412</span>"
  )
  expect_match(as.character(show_count(cohort_flow, "n_excluded", format = "html")), ">&lt;5</span>$")
  expect_identical(show_count(cohort_flow, "n_excluded", format = "text"), "<5")
  expect_identical(show_count(cohort_flow, "n_screened", format = "auto"), "412")
  expect_error(show_count(cohort_flow, "n_missing"), class = "dctools_display_error")
  expect_error(show_count(cohort_flow, "~hidden"), class = "dctools_display_error")
  expect_error(show_count(list(), "n_screened", target = "x"), class = "dctools_display_error")
  expect_error(show_count(flow_report(), "n_screened"), class = "dctools_display_error")
  expect_error(show_count(cohort_flow, "n_screened", rule = "percent"), class = "dctools_display_error")
})

test_that("masking is recomputed, not taken from a resolver stored in the report", {
  cohort_flow <- flow_report()
  cohort_flow$resolver <- function(x) "999"
  expect_identical(show_count(cohort_flow, "n_excluded", format = "text"), "<5")
})

test_that("a page whose values all came through show_count passes, with its insertion records", {
  cohort_flow <- flow_report()
  path <- write_page(page(
    "<h2>Screening</h2>",
    paste0("<p>In 2026, ", show_count(cohort_flow, "n_screened", format = "html"), " were screened.</p>"),
    "<h2>Exclusions</h2>",
    paste0("<p>", show_count(cohort_flow, "n_excluded", format = "html"), " were excluded.</p>")
  ))
  res <- check_rendered_values(path, list(cohort_flow = cohort_flow))
  expect_identical(res$outcome, "pass", info = paste(res$problems, collapse = "; "))
  expect_identical(
    lapply(res$insertions, function(x) x[c("id", "display", "section")]),
    list(
      list(id = "n_screened", display = "412", section = "Screening"),
      list(id = "n_excluded", display = "<5", section = "Exclusions")
    )
  )
})

test_that("a changed value, an unknown count and a bare number fail", {
  cohort_flow <- flow_report()
  span <- as.character(show_count(cohort_flow, "n_screened", format = "html"))
  path <- write_page(page(
    paste0("<p>", sub(">412<", ">413<", span, fixed = TRUE), "</p>"),
    paste0("<p>", sub("n_screened", "n_other", span, fixed = TRUE), "</p>"),
    paste0("<p>", sub("cohort_flow", "elsewhere", span, fixed = TRUE), "</p>"),
    "<p>Of 412 screened, 3.5% were excluded.</p>"
  ))
  res <- check_rendered_values(path, list(cohort_flow = cohort_flow))
  expect_identical(res$outcome, "fail")
  expect_true(any(grepl("value 1 \\(cohort_flow / n_screened\\): shows 413, the report prints 412", res$problems)))
  expect_true(any(grepl("value 2 .*not a printed count of cohort_flow", res$problems)))
  expect_true(any(grepl("value 3 .*no available report for target elsewhere", res$problems)))
  expect_true("bare number 412 outside an inserted value" %in% res$problems)
  expect_true("bare number 3.5 outside an inserted value" %in% res$problems)
  # Numbers in the head, scripts and styles are not visible text.
  expect_false(any(grepl("12345|300", res$problems)))
})

test_that("exemptions are explicit, and only HTML is checked", {
  cohort_flow <- flow_report()
  path <- write_page(page("<p>Protocol 17, version 2.</p>"))
  expect_identical(check_rendered_values(path, list(cohort_flow = cohort_flow))$outcome, "fail")
  expect_identical(
    check_rendered_values(path, list(cohort_flow = cohort_flow), exempt = c("^17$", "^2$"))$outcome,
    "pass"
  )
  docx <- withr::local_tempfile(fileext = ".docx")
  writeLines("x", docx)
  expect_identical(check_rendered_values(docx, list())$outcome, "not_established")
  expect_identical(check_rendered_values(file.path(tempdir(), "none.html"), list())$outcome, "fail")
})

# AUD-005: a page with nothing to check is not a pass.
test_that("a page with no inserted value and no number is not established, and counts are reported", {
  cohort_flow <- flow_report()
  figure <- write_page(page(
    "<p>The estimated effect is shown in the figure below.</p>",
    "<img src=\"forest.png\" alt=\"forest plot\">"
  ))
  res <- check_rendered_values(figure, list(cohort_flow = cohort_flow))
  expect_identical(res$outcome, "not_established")
  expect_identical(res$problems, "no values checked")
  expect_identical(c(res$n_insertions, res$n_bare_numbers), c(0L, 0L))
  # Controls: an inserted value passes with its count; a typed-in estimate
  # still fails as a bare number (AUD-008).
  ok <- write_page(page(paste0("<p>", show_count(cohort_flow, "n_screened", format = "html"), " screened.</p>")))
  res_ok <- check_rendered_values(ok, list(cohort_flow = cohort_flow))
  expect_identical(res_ok$outcome, "pass")
  expect_identical(c(res_ok$n_insertions, res_ok$n_bare_numbers), c(1L, 0L))
  typed <- write_page(page("<p>The hazard ratio was 0.72 (95% CI 0.61 to 0.85).</p>"))
  res_typed <- check_rendered_values(typed, list(cohort_flow = cohort_flow))
  expect_identical(res_typed$outcome, "fail")
  expect_true("bare number 0.72 outside an inserted value" %in% res_typed$problems)
  # 0.72, 95, 0.61 and 0.85; the head's "2026" is not visible text.
  expect_identical(res_typed$n_bare_numbers, 4L)
})
