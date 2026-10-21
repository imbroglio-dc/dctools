audit_copy <- function(proj, ...) {
  withr::with_dir(
    proj,
    audit_run(
      fixture_ledger_path("."),
      store = "_targets",
      script = "_targets.R",
      ...
    )
  )
}

status_of <- function(result, check) result$status[result$check == check]

test_that("the untouched fixture passes C1-C3", {
  skip_ledger_fixture()
  local_engine()
  result <- audit_copy(copy_fixture())
  expect_identical(status_of(result, "C1"), "PASS")
  expect_identical(status_of(result, "C2"), "PASS")
  expect_identical(status_of(result, "C3"), "PASS")
  expect_identical(result$name[result$check == "C1"], "Code")
})

test_that("C1 fails when a recorded code snippet does not match the commit", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$provenance[[1]]$code <- "    made_up_line()"
    l
  })
  result <- audit_copy(proj)
  expect_identical(status_of(result, "C1"), "FAIL")
  expect_match(
    result$detail[result$check == "C1"][[1]],
    "differs from the recorded code",
    all = FALSE
  )
})

test_that("C1 fails for an unknown commit and for a run made with uncommitted changes", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$code$sha <- strrep("0", 40)
    l
  })
  expect_identical(status_of(audit_copy(proj), "C1"), "FAIL")
  proj2 <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj2), function(l) {
    l$code$clean <- FALSE
    l
  })
  expect_identical(status_of(audit_copy(proj2), "C1"), "FAIL")
})

test_that("C1 fails when the recorded function span does not match the commit", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$provenance[[1]]$function_line_end <- 99L
    l
  })
  expect_identical(status_of(audit_copy(proj), "C1"), "FAIL")
})

test_that("C2 fails when a ledger hash or a stored object differs from the store", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$targets[[1]]$data <- "0000000000000000"
    l
  })
  expect_identical(status_of(audit_copy(proj), "C2"), "FAIL")
  proj2 <- copy_fixture()
  cat(
    "x",
    file = file.path(proj2, "_targets", "objects", "values"),
    append = TRUE
  )
  result <- audit_copy(proj2)
  expect_identical(status_of(result, "C2"), "FAIL")
  expect_match(result$detail[result$check == "C2"][[1]], "values", all = FALSE)
})

test_that("C3 fails when the code changed after the run", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  f <- file.path(proj, "R", "evidence.R")
  writeLines(sub("values > 2", "values > 3", readLines(f), fixed = TRUE), f)
  result <- audit_copy(proj)
  expect_identical(status_of(result, "C3"), "FAIL")
  expect_match(
    result$detail[result$check == "C3"][[1]],
    "evidence",
    all = FALSE
  )
})

test_that(".check_result never passes an empty check", {
  r <- .check_result("C6", .items(), "no decision links in the ledger")
  expect_identical(r$status, "NOT EVALUATED")
  expect_identical(r$detail[[1]], "no decision links in the ledger")
  r2 <- .check_result(
    "C6",
    .bind_items(list(.item("a", TRUE), .item("b", FALSE, "why"))),
    ""
  )
  expect_identical(r2$status, "FAIL")
  expect_identical(r2$n_evaluated, 2L)
  expect_identical(r2$detail[[1]], "b: why")
})

test_that("audit_run stops before checking when a reportable target is unsafe", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$reportable[[1]]$name <- "values"
    l
  })
  expect_error(audit_copy(proj), class = "dctools_audit_unsafe_error")
  expect_false(file.exists(file.path(
    proj,
    "docs",
    "runs",
    paste0(fixture_run_id, ".md")
  )))
})
