scrub <- function(x) {
  x <- gsub("[0-9a-f]{64}", "<sha256>", x)
  gsub("[0-9a-f]{40}", "<sha>", x)
}

run_fixture_audit <- function(proj) {
  withr::with_dir(
    proj,
    audit_run(
      fixture_ledger_path("."),
      store = "_targets",
      script = "_targets.R"
    )
  )
}

test_that("the audit page shows the verdict, one row per check and how to verify by hand", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  run_fixture_audit(proj)
  md <- readLines(file.path(
    proj,
    "docs",
    "runs",
    paste0(fixture_run_id, ".md")
  ))
  expect_identical(md[1], paste0("# Run ", fixture_run_id, " audit: PASS"))
  expect_length(grep("^\\| C[1-9] \\|", md), 9L)
  expect_true(any(grepl("https://example.com/o/r/tree/", md, fixed = TRUE)))
  expect_false(any(grepl("secret", md)))
  expect_true(any(grepl("'data/raw/input values.csv'", md, fixed = TRUE)))
  expect_true(any(grepl(
    "^git show '[0-9a-f]{40}:R/evidence.R' \\| sed -n '4,4p'   # C1: ",
    md
  )))
  expect_snapshot(cat(scrub(md), sep = "\n"))
})

test_that("an invalid commit in the ledger is never put into a command or link", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$code$sha <- "x; rm -rf /"
    l
  })
  run_fixture_audit(proj)
  md <- readLines(file.path(
    proj,
    "docs",
    "runs",
    paste0(fixture_run_id, ".md")
  ))
  expect_false(any(grepl("^git .*rm -rf", md)))
  expect_false(any(grepl("](", md[grepl("Commit:", md)], fixed = TRUE)))
  expect_true(any(grepl("not a valid SHA", md, fixed = TRUE)))
  expect_false(any(grepl("^git ", md)))
})

test_that("failures are listed, ten at most per check", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$links <- lapply(1:12, function(i) {
      list(
        decision_id = paste0("X", i),
        decision_status = "open",
        target = "nope",
        role = "evidence"
      )
    })
    l
  })
  run_fixture_audit(proj)
  md <- readLines(file.path(
    proj,
    "docs",
    "runs",
    paste0(fixture_run_id, ".md")
  ))
  expect_true("### C6 Decisions: FAIL" %in% md)
  expect_true("- ... and 2 more (see the ledger)" %in% md)
})

test_that("the provenance page shows each masked value with its code and a permalink", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  run_fixture_audit(proj)
  pm <- readLines(file.path(
    proj,
    "docs",
    "runs",
    paste0(fixture_run_id, ".provenance.md")
  ))
  expect_true("## R/evidence.R" %in% pm)
  expect_true("### build_evidence() (lines 1-8)" %in% pm)
  expect_true(any(grepl("`evidence` / `n_values` = `12`", pm, fixed = TRUE)))
  expect_true(any(grepl("`evidence` / `n_large` = `10`", pm, fixed = TRUE)))
  expect_true(any(grepl("/blob/[0-9a-f]{40}/R/evidence.R#L4-L4", pm)))
  expect_true(any(grepl("^  4 \\| ", pm)))
  expect_snapshot(cat(scrub(pm), sep = "\n"))
})

test_that(".resolve_value masks small counts and marks unprinted ones", {
  r <- create_report()
  record_count(r, "small", 3)
  record_count(r, "big", 30)
  record_unprinted_count(r, "~gap", 1)
  expect_identical(.resolve_value(r, "small"), "<5")
  expect_identical(.resolve_value(r, "big"), "30")
  expect_identical(.resolve_value(r, "~gap"), "(not printed)")
  expect_identical(.resolve_value(NULL, "x"), "(report not available)")
})

test_that("masked values are code-formatted so markdown does not swallow them", {
  r <- create_report()
  record_count(r, "small", 3)
  ledger <- list(
    run = list(run_id = "r1"),
    code = list(sha = strrep("a", 40), remote = "https://example.com/o/r.git"),
    provenance = list(list(
      report = "rep",
      id = "small",
      file = "R/x.R",
      function_name = "f",
      function_line_start = 1L,
      function_line_end = 3L,
      line_start = 2L,
      line_end = 2L,
      code = "record_count(r, 'small', 3)"
    ))
  )
  pm <- .render_provenance_md(ledger, list(rep = r))
  expect_true(
    "- `rep` / `small` = `<5` ([L2-L2](https://example.com/o/r/blob/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/R/x.R#L2-L2))" %in%
      pm
  )
})

test_that("a failed check with no detail lists no empty bullet", {
  ledger <- list(run = list(run_id = "r1"), code = list(sha = strrep("a", 40)))
  result <- data.frame(
    check = "C1",
    name = "Code",
    status = "FAIL",
    n_evaluated = 1L,
    n_failed = 1L
  )
  result$detail <- list(character(0))
  attr(result, "verdict") <- "FAIL"
  md <- .render_audit_md(ledger, result)
  expect_false("- " %in% md)
})

test_that(".web_url strips credentials", {
  expect_identical(
    .web_url("https://u:tok@github.com/o/r.git"),
    "https://github.com/o/r"
  )
})

test_that("the provenance page recomputes masking, ignoring a stored resolver", {
  r <- create_report()
  record_count(r, "n", 3)
  # A stale or tampered resolver in the stored object prints the exact value.
  r$resolver <- function(text) gsub("\\{\\{n\\}\\}", "3", text)
  r$decision <- list()
  ledger <- list(
    run = list(run_id = "20260101-000000"),
    code = list(sha = NA),
    provenance = list(list(
      report = "rep",
      id = "n",
      file = "R/a.R",
      line_start = 1L,
      line_end = 1L,
      code = "x",
      function_name = "f"
    ))
  )
  pm <- .render_provenance_md(ledger, list(rep = r))
  expect_true(any(grepl("`rep` / `n` = `<5`", pm, fixed = TRUE)))
  expect_false(any(grepl("= `3`", pm, fixed = TRUE)))
})

test_that("an anonymous function is shown as such on the provenance page", {
  ledger <- list(
    run = list(run_id = "20260101-000000"),
    code = list(sha = NA),
    provenance = list(list(
      report = "rep",
      id = "n",
      file = "R/a.R",
      line_start = 2L,
      line_end = 2L,
      code = "x",
      function_name = "(anonymous function)",
      function_line_start = 2L,
      function_line_end = 2L
    ))
  )
  r <- create_report()
  record_count(r, "n", 30)
  pm <- .render_provenance_md(ledger, list(rep = r))
  expect_true("### (anonymous function) (lines 2-2)" %in% pm)
})

test_that("verify-by-hand commands use sh quoting on every platform", {
  expect_identical(.sh_quote("a b"), "'a b'")
  # sh quoting, never cmd's: a single quote goes inside double quotes.
  expect_identical(.sh_quote("it's"), "\"it's\"")
})

test_that(".first_code_ref skips absolute paths, Windows ones included", {
  prov <- list(
    list(file = "C:/proj/R/a.R", line_start = 1L, line_end = 1L),
    list(file = "/proj/R/a.R", line_start = 1L, line_end = 1L),
    list(file = "R/a.R", line_start = 2L, line_end = 3L)
  )
  expect_identical(
    .first_code_ref(prov),
    list(file = "R/a.R", start = 2L, end = 3L)
  )
})
