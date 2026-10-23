# Synthetic-vector tests of the report's small-cell suppression (ported from
# sepsis_burn tests/testthat/test-disclosure-safe-report.R). No data files are read.
#
# Adversary model (exact, brute force): a printed value is exact; a "<5" cell is
# known to be 1..4; a "<suppr." cell is known to be 5..cap; an unprinted "~"
# quantity is 0..cap; every registered equation holds. For each "<5" cell the
# feasible set must still contain EVERY value 1..4 (no narrowing at all).

# Feasible values of each primary-hidden var, given what is printed.
feasible_values_of_small_counts <- function(
  report,
  decision,
  cap = .count_upper_bound(report)
) {
  hidden <- c(decision$small_count_ids, decision$suppressed_ids)
  eq_ids <- unique(unlist(lapply(report$relations, function(relation) {
    names(relation$coefficients)
  })))
  free <- eq_ids[startsWith(eq_ids, "~")]
  unknown <- union(hidden[hidden %in% eq_ids], free)
  # Hidden vars in no equation are unconstrained: nothing to recover.
  dom <- lapply(unknown, function(id) {
    if (id %in% decision$small_count_ids) {
      1:4
    } else if (startsWith(id, "~")) {
      0:cap
    } else {
      5:cap
    }
  })
  names(dom) <- unknown
  grid <- do.call(expand.grid, c(dom, list(KEEP.OUT.ATTRS = FALSE)))
  ok <- rep(TRUE, nrow(grid))
  for (relation in report$relations) {
    tot <- rep(0, nrow(grid))
    for (id in names(relation$coefficients)) {
      x <- if (id %in% unknown) grid[[id]] else report$counts[[id]]
      tot <- tot + relation$coefficients[[id]] * x
    }
    ok <- ok & tot == 0
  }
  out <- lapply(intersect(decision$small_count_ids, unknown), function(id) {
    sort(unique(grid[[id]][ok]))
  })
  names(out) <- intersect(decision$small_count_ids, unknown)
  out
}

expect_no_small_count_recoverable <- function(report) {
  decision <- .decide_which_counts_to_hide(report)
  feas <- feasible_values_of_small_counts(report, decision)
  for (id in names(feas)) {
    expect_equal(feas[[id]], 1:4, info = paste("cell", id, "narrowed"))
  }
  decision
}

test_that("primary masking: 1-4 hidden, 0 and >= 5 shown", {
  report <- create_report()
  ids <- c(
    record_count(report, "a", 0),
    record_count(report, "b", 4),
    record_count(report, "c", 5),
    record_count(report, "d", 1)
  )
  decision <- .decide_which_counts_to_hide(report)
  expect_setequal(decision$small_count_ids, c("b", "d"))
  expect_equal(.format_count(report, decision, "a"), "0")
  expect_equal(.format_count(report, decision, "b"), "<5")
  expect_equal(.format_count(report, decision, "c"), "5")
})

test_that("a group with a small cell does not print its total", {
  report <- create_report()
  record_count(report, "c1", 3)
  record_count(report, "c2", 7)
  record_count(report, "c3", 6)
  record_count(report, "T", 16)
  declare_sum_relation(report, c("c1", "c2", "c3"), "T")
  decision <- expect_no_small_count_recoverable(report)
  expect_true("T" %in% decision$suppressed_ids)
})

test_that("a zero-only companion still hides the total", {
  report <- create_report()
  record_count(report, "c1", 3)
  record_count(report, "c2", 0)
  record_count(report, "c3", 0)
  record_count(report, "T", 3)
  declare_sum_relation(report, c("c1", "c2", "c3"), "T")
  decision <- expect_no_small_count_recoverable(report)
  expect_equal(.format_count(report, decision, "c2"), "0")
  expect_true(.format_count(report, decision, "T") %in% c("<5", "<suppr.>"))
})

test_that("a second partition of the same total cannot be used to recover the cell", {
  report <- create_report()
  record_count(report, "a1", 3)
  record_count(report, "a2", 7)
  record_count(report, "a3", 6)
  record_count(report, "b1", 9)
  record_count(report, "b2", 7)
  record_count(report, "T", 16)
  declare_sum_relation(report, c("a1", "a2", "a3"), "T")
  declare_sum_relation(report, c("b1", "b2"), "T")
  expect_no_small_count_recoverable(report)
})

test_that("(1,5,9) with protected total 15: the smallest-first rule leaked c1 = 1", {
  report <- create_report()
  record_count(report, "c1", 1)
  record_count(report, "c2", 5)
  record_count(report, "c3", 9)
  record_count(report, "T", 15, protect = TRUE)
  declare_sum_relation(report, c("c1", "c2", "c3"), "T")
  decision <- expect_no_small_count_recoverable(report)
  expect_equal(decision$suppressed_ids, "c3") # the LARGEST non-protected count is hidden
  expect_equal(.format_count(report, decision, "c2"), "5")
  expect_equal(.format_count(report, decision, "T"), "15")
})

test_that("(2,6,9) with protected total 17: no narrowing to 1..3", {
  report <- create_report()
  record_count(report, "c1", 2)
  record_count(report, "c2", 6)
  record_count(report, "c3", 9)
  record_count(report, "T", 17, protect = TRUE)
  declare_sum_relation(report, c("c1", "c2", "c3"), "T")
  expect_no_small_count_recoverable(report)
})

test_that("two small cells in one row of a group with a protected total", {
  report <- create_report()
  record_count(report, "c1", 2)
  record_count(report, "c2", 3)
  record_count(report, "c3", 15)
  record_count(report, "T", 20, protect = TRUE)
  declare_sum_relation(report, c("c1", "c2", "c3"), "T")
  expect_no_small_count_recoverable(report)
})

test_that("small cell next to a zero cell", {
  report <- create_report()
  record_count(report, "c1", 3)
  record_count(report, "c2", 0)
  record_count(report, "c3", 12)
  record_count(report, "T", 15, protect = TRUE)
  declare_sum_relation(report, c("c1", "c2", "c3"), "T")
  decision <- expect_no_small_count_recoverable(report)
  expect_equal(.format_count(report, decision, "c2"), "0")
})

test_that("a count and its complement in another table (clinical - admission = no NPX)", {
  report <- create_report()
  record_count(report, "clin", 20)
  record_count(report, "adm", 17, protect = TRUE)
  record_count(report, "none", 3)
  declare_linear_relation(report, c(clin = 1, adm = -1, none = -1))
  expect_no_small_count_recoverable(report)
})

test_that("a hidden count that is fixed by another table cannot serve as the buffer", {
  # b is hidden as the largest candidate, but a second relation pins it via d;
  # the algorithm must keep going (hide d as well) until no narrowing remains.
  report <- create_report()
  cells <- c(a = 3, b = 9, c = 8, d = 7)
  for (i in names(cells)) {
    record_count(report, i, cells[[i]])
  }
  record_count(report, "r1", 12, protect = TRUE)
  record_count(report, "r2", 15, protect = TRUE)
  record_count(report, "k1", 11, protect = TRUE)
  record_count(report, "k2", 16, protect = TRUE)
  declare_sum_relation(report, c("a", "b"), "r1")
  declare_sum_relation(report, c("c", "d"), "r2")
  declare_sum_relation(report, c("a", "c"), "k1")
  declare_sum_relation(report, c("b", "d"), "k2")
  expect_no_small_count_recoverable(report)
})

test_that("an unrelated large count is left alone", {
  report <- create_report()
  record_count(report, "x", 2)
  record_count(report, "y", 40)
  decision <- .decide_which_counts_to_hide(report)
  expect_equal(decision$suppressed_ids, character(0))
  expect_equal(.format_count(report, decision, "y"), "40")
})

test_that("rendering: tokens resolved, total of a small-cell table not printed, pct withheld", {
  report <- create_report()
  record_count(report, "T", 16)
  t1 <- add_count_table(
    report,
    "t",
    table(c(
      "a",
      "a",
      "a",
      "b",
      "b",
      "b",
      "b",
      "b",
      "b",
      "b",
      "b",
      "b",
      "b",
      "b",
      "b",
      "b"
    )),
    labels_from_code = TRUE,
    total_id = "T"
  )
  add_line(report, "total: ", "{{T}}")
  add_data_frame(
    report,
    data.frame(p = "{{pct:t.1,t.2}}", stringsAsFactors = FALSE)
  )
  out <- capture.output(render_report(report))
  txt <- paste(out, collapse = "\n")
  expect_match(txt, "total: <suppr.>", fixed = TRUE)
  expect_match(txt, "<5", fixed = TRUE)
  expect_false(grepl("\\{\\{", txt))
  expect_match(txt, "-", fixed = TRUE)
})

test_that("labels: only short identifier-like labels are printed", {
  expect_equal(
    .sanitize_labels(c(
      "Complete",
      "a b.c-d_1",
      NA,
      "Jean Dupont 01/02/1950",
      strrep("x", 21)
    )),
    c("Complete", "a b.c-d_1", NA, "<other>", "<other>")
  )
})

test_that("labels from data holding a bare number print as <other>", {
  expect_equal(
    .sanitize_labels(c("31", "57", "1985-03-12", "J7", "a b.c-d_1", NA)),
    c("<other>", "<other>", "<other>", "J7", "a b.c-d_1", NA)
  )
  r <- create_report()
  add_tabulation(r, "age", c(31, 31, 57))
  out <- paste(capture.output(render_report(r)), collapse = "\n")
  expect_false(grepl("31|57", out))
  r2 <- create_report()
  add_tabulation(r2, "flag", c(0, 1, 1), labels_from_code = TRUE)
  expect_match(
    paste(capture.output(render_report(r2)), collapse = "\n"),
    "0 +1"
  )
})

test_that("count ids must be identifier-like", {
  r <- create_report()
  for (bad in c("a b", "1n", "n-1", "", "n{{x}}", "~")) {
    expect_error(record_count(r, bad, 1), class = "dctools_report_id_error")
  }
  expect_error(
    record_unprinted_count(r, "~a b", 1),
    class = "dctools_report_id_error"
  )
  expect_error(
    add_count_table(r, "t 1", table(c("a", "b"))),
    class = "dctools_report_id_error"
  )
  expect_error(
    add_tabulation(r, "t-1", c("a", "b")),
    class = "dctools_report_id_error"
  )
  expect_identical(record_count(r, "n_ok.2", 1), "{{n_ok.2}}")
  expect_identical(record_unprinted_count(r, "~gap", 1), "~gap")
  add_count_table(r, "tab", table(c("a", "b")))
  expect_true(all(c("tab.1", "tab.2") %in% names(r$counts)))
})

test_that("section: a failure prints only its class, warnings are only counted", {
  report <- create_report()
  run_section(report, "boom", stop(strrep("z", 900)))
  run_section(report, "warn", warning("secret-looking text"))
  expect_equal(report$n_failed_sections, 1L)
  expect_equal(report$n_warnings, 1L)
  txt <- paste(capture.output(render_report(report)), collapse = "\n")
  expect_false(grepl("zzz", txt))
  expect_match(txt, "SECTION FAILED: simpleError", fixed = TRUE)
  expect_false(grepl("secret-looking", txt))
})

test_that("random small groups sharing a total: no '<5' cell is narrowed", {
  set.seed(20260918)
  n_checked <- 0L
  for (k in 1:60) {
    a <- sample(0:12, sample(2:3, 1), replace = TRUE)
    b <- sample(0:12, 2, replace = TRUE)
    b[2] <- sum(a) - b[1]
    if (b[2] < 0 || sum(a) < 5) {
      next
    } # a total below 5 makes every cell small: inherent
    report <- create_report()
    for (i in seq_along(a)) {
      record_count(report, paste0("a", i), a[i])
    }
    for (i in seq_along(b)) {
      record_count(report, paste0("b", i), b[i])
    }
    record_count(report, "T", sum(a), protect = sample(c(TRUE, FALSE), 1))
    declare_sum_relation(report, paste0("a", seq_along(a)), "T")
    declare_sum_relation(report, paste0("b", seq_along(b)), "T")
    decision <- .decide_which_counts_to_hide(report)
    if (
      length(unique(c(decision$small_count_ids, decision$suppressed_ids))) > 4L
    ) {
      next
    } # brute force too large
    expect_no_small_count_recoverable(report)
    n_checked <- n_checked + 1L
  }
  expect_gt(n_checked, 15L)
})

# ---- Printing one section at a time ----

make_two_section_report <- function() {
  report <- create_report()
  for (section_number in 1:2) {
    run_section(
      report,
      paste("Part", section_number),
      section_id = paste0("part", section_number),
      {
        # Part 1 holds a small count whose total sits in Part 2.
        count <- record_count(
          report,
          paste0("n", section_number),
          c(3, 40)[section_number]
        )
        add_line(report, "count: ", count)
      }
    )
  }
  record_count(report, "total", 43)
  declare_sum_relation(report, c("n1", "n2"), "total")
  run_section(
    report,
    "closing",
    add_line(report, "total: {{total}}"),
    heading = FALSE
  )
  report
}

test_that("a section printed alone matches the same lines of the full report", {
  report <- make_two_section_report()
  part1 <- capture.output(print_report_section(report, "part1"))
  part2 <- capture.output(print_report_section(report, "part2"))
  full <- capture.output(render_report(make_two_section_report()))

  expect_equal(part1, "count: <5")
  expect_true(all(c(part1, part2) %in% full))
  expect_false(any(grepl("Part", c(part1, part2)))) # no heading by default
})

test_that("headings are kept on request and name the title, not the loop variable", {
  report <- make_two_section_report()
  expect_match(
    capture.output(print_report_section(
      report,
      "part1",
      include_heading = TRUE
    )),
    "-- Part 1 --",
    fixed = TRUE,
    all = FALSE
  )
  expect_match(
    capture.output(print_report_section(
      report,
      "part2",
      include_heading = TRUE
    )),
    "-- Part 2 --",
    fixed = TRUE,
    all = FALSE
  )
})

test_that("an unknown section id is an error that lists the known ids", {
  report <- make_two_section_report()
  expect_error(
    print_report_section(report, "nope"),
    "known ids: part1, part2, closing"
  )
})

test_that("counts cannot be registered once the report has been prepared for printing", {
  report <- make_two_section_report()
  invisible(capture.output(print_report_section(report, "part1")))
  expect_error(record_count(report, "late", 1), "already been prepared")
  expect_error(
    declare_sum_relation(report, "n1", "total"),
    "already been prepared"
  )
  expect_error(
    record_unprinted_count(report, "~late", 1),
    "already been prepared"
  )
})

# ---- Printing every count exactly ----

test_that("with hide_small_counts = FALSE small counts and totals print exactly", {
  report <- create_report(hide_small_counts = FALSE)
  small <- record_count(report, "small", 3)
  large <- record_count(report, "large", 40)
  total <- record_count(report, "total", 43)
  declare_sum_relation(report, c("small", "large"), "total")
  add_line(report, "small: ", small, "; large: ", large, "; total: ", total)

  printed <- capture.output(render_report(report))

  expect_true("small: 3; large: 40; total: 43" %in% printed)
  expect_false(any(grepl("<5|<suppr", printed)))
  expect_match(printed[1], "all counts are exact", fixed = TRUE)
  expect_equal(report$decision$suppressed_ids, character(0))
})

test_that("small-count hiding is on by default", {
  expect_true(create_report()$hide_small_counts)
})

test_that("run_section: with an error_sink, the report shows the class, not the message", {
  seen <- NULL
  report <- create_report(
    hide_small_counts = FALSE,
    error_sink = function(condition) seen <<- conditionMessage(condition)
  )
  run_section(report, "s", stop("secret value 42"), section_id = "s")
  printed <- paste(
    capture.output(print_report_section(report, "s")),
    collapse = "\n"
  )
  expect_false(grepl("secret value 42", printed))
  expect_match(printed, "SECTION FAILED: simpleError")
  expect_identical(seen, "secret value 42")
})

test_that("create_report returns a classed report that records the engine version", {
  r <- create_report()
  expect_s3_class(r, "dctools_report")
  expect_identical(
    r$dctools_version,
    as.character(utils::packageVersion("dctools"))
  )
  expect_identical(r$section_ids, character(0))
  expect_error(create_report(error_sink = "x"), "error_sink")
})

test_that("run_section records its section id, with or without a heading", {
  r <- create_report()
  run_section(r, "A title", add_line(r, "x"))
  run_section(r, "quiet", add_line(r, "y"), heading = FALSE)
  expect_identical(r$section_ids, c("A title", "quiet"))
  out <- capture.output(print_report_section(
    r,
    "quiet",
    include_heading = TRUE
  ))
  expect_identical(out, "y")
})

test_that("add_count_table: a dimension over max_levels prints only a note", {
  r <- create_report()
  res <- withVisible(
    add_count_table(r, "big", table(letters[1:5]), max_levels = 3L)
  )
  expect_false(res$visible)
  expect_null(res$value)
  expect_length(r$counts, 0L)
  out <- capture.output(render_report(r))
  expect_true("  (5 levels; not printed)" %in% out)
  expect_false(any(grepl("big", out, fixed = TRUE)))
  expect_false(any(grepl("^\\s*[a-e]\\s+[0-9]", out)))
})
