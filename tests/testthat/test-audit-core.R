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

detail_of <- function(result, check) result$detail[result$check == check][[1]]
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
  r <- audit_copy(proj)
  expect_identical(status_of(r, "C1"), "FAIL")
  expect_match(detail_of(r, "C1"), "not in this repository", all = FALSE)
  proj2 <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj2), function(l) {
    l$code$clean <- FALSE
    l
  })
  r2 <- audit_copy(proj2)
  expect_identical(status_of(r2, "C1"), "FAIL")
  expect_match(detail_of(r2, "C1"), "uncommitted changes", all = FALSE)
})

test_that("C1 fails when the recorded function span does not match the commit", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$provenance[[1]]$function_line_end <- 99L
    l
  })
  r <- audit_copy(proj)
  expect_identical(status_of(r, "C1"), "FAIL")
  expect_match(detail_of(r, "C1"), "is not defined at", all = FALSE)
})

test_that("C2 fails when a ledger hash or a stored object differs from the store", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$targets[[1]]$data <- "0000000000000000"
    l
  })
  r <- audit_copy(proj)
  expect_identical(status_of(r, "C2"), "FAIL")
  expect_match(detail_of(r, "C2"), "differs: data", all = FALSE)
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
  r3 <- .check_result("C6", .bind_items(list(.item("a", TRUE))), "")
  expect_identical(r3$status, "PASS")
  expect_identical(r3$detail[[1]], character(0))
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

c1_fails <- function(mutate, pattern) {
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), mutate)
  r <- audit_copy(proj)
  expect_identical(status_of(r, "C1"), "FAIL")
  expect_match(detail_of(r, "C1"), pattern, all = FALSE)
}

test_that("C1 rejects a symbolic or short sha", {
  skip_ledger_fixture()
  local_engine()
  c1_fails(
    function(l) {
      l$code$sha <- "HEAD"
      l
    },
    "not a full commit SHA"
  )
})

test_that("C1 fails on null provenance code or line_start", {
  skip_ledger_fixture()
  local_engine()
  c1_fails(
    function(l) {
      l$provenance[[1]]$code <- NULL
      l$provenance[[1]]["code"] <- list(NULL)
      l
    },
    "differs from the recorded code"
  )
  c1_fails(
    function(l) {
      l$provenance[[1]]["line_start"] <- list(NULL)
      l
    },
    "missing or outside"
  )
})

test_that("C2 fails for a ledger target absent from the store and vice versa", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    ghost <- l$targets[[1]]
    ghost$name <- "ghost"
    l$targets <- c(l$targets, list(ghost))
    l
  })
  r <- audit_copy(proj)
  expect_identical(status_of(r, "C2"), "FAIL")
  expect_match(detail_of(r, "C2"), "ghost: not in the store", all = FALSE)
  proj2 <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj2), function(l) {
    l$targets <- l$targets[-1]
    l
  })
  r2 <- audit_copy(proj2)
  expect_identical(status_of(r2, "C2"), "FAIL")
  expect_match(
    detail_of(r2, "C2"),
    "in the store but not in the ledger",
    all = FALSE
  )
})

test_that("C2 fails explicitly for a ledger target with no name", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$targets[[1]]["name"] <- list(NULL)
    l
  })
  r <- audit_copy(proj)
  expect_identical(status_of(r, "C2"), "FAIL")
  expect_match(detail_of(r, "C2"), "a ledger target has no name", all = FALSE)
})

test_that("C3 fails when the ledger lacks or records outdated targets", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$outdated <- NULL
    l
  })
  r <- audit_copy(proj)
  expect_identical(status_of(r, "C3"), "FAIL")
  expect_match(
    detail_of(r, "C3"),
    "does not record outdated targets",
    all = FALSE
  )
  proj2 <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj2), function(l) {
    l$outdated <- list("evidence")
    l
  })
  r2 <- audit_copy(proj2)
  expect_identical(status_of(r2, "C3"), "FAIL")
  expect_match(detail_of(r2, "C3"), "evidence", all = FALSE)
})

# Counts recorded inside an anonymous function (lapply) or a nested helper,
# checked against their own source the way C1 checks them against git.
nested_provenance <- function() {
  local_mocked_bindings(
    .current_target = function() "rep",
    .env = parent.frame()
  )
  env <- source_user_code(
    c(
      "build <- function(d) {",
      "  r <- dctools::create_report()",
      "  lapply(c('a', 'b'), function(g) dctools::record_count(r, paste0('n_', g), sum(d == g)))",
      "  add <- function(id, v) dctools::record_count(r, id, v)",
      "  add('n', length(d))",
      "  r",
      "}"
    ),
    .local_envir = parent.frame()
  )
  r <- env$build(c("a", "b", "b", "a", "a"))
  dir <- dirname(r$provenance[[1]]$file)
  list(
    provenance = lapply(r$provenance, function(p) {
      p$file <- basename(p$file)
      p$function_file <- basename(p$function_file)
      p$report <- "rep"
      p
    }),
    show = function(f) readLines(file.path(dir, f))
  )
}

test_that("C1 accepts counts recorded in anonymous and nested functions", {
  x <- nested_provenance()
  expect_setequal(names(x$provenance), c("n_a", "n_b", "n"))
  for (p in x$provenance) {
    it <- .check_snippet(p, show = x$show)
    expect_true(it$ok, info = paste(p$id, it$detail))
  }
  expect_identical(
    c(x$provenance$n$function_line_start, x$provenance$n$function_line_end),
    c(4L, 4L)
  )
})

test_that("C1 still fails a function span that matches no function at the commit", {
  x <- nested_provenance()
  for (id in c("n_a", "n")) {
    p <- x$provenance[[id]]
    p$function_line_end <- 5L
    it <- .check_snippet(p, show = x$show)
    expect_false(it$ok)
    expect_match(it$detail, "is not defined at user.R:")
  }
})

test_that("C1 fails a function span whose recorded name is not the definition's", {
  x <- nested_provenance()
  p <- x$provenance$n
  p$function_name <- "build"
  expect_false(.check_snippet(p, show = x$show)$ok)
  p <- x$provenance$n_a
  p$function_name <- "add"
  expect_false(.check_snippet(p, show = x$show)$ok)
})

test_that(".function_defs lists every function expression, named or not", {
  defs <- .function_defs(c(
    "h = function() 2",
    "build <- function() {",
    "  inner <- function() 1",
    "  lapply(1, FUN = function(z) z)",
    "  \\(x) x",
    "}"
  ))
  expect_identical(defs$line_start, c(1L, 2L, 3L, 4L, 5L))
  expect_identical(defs$line_end, c(1L, 6L, 3L, 4L, 5L))
  expect_identical(defs$name, c("h", "build", "inner", NA, NA))
  expect_identical(nrow(.function_defs("not ( valid")), 0L)
})
