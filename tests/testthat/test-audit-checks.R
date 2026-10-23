audit_copy <- function(proj) {
  withr::with_dir(
    proj,
    audit_run(
      fixture_ledger_path("."),
      store = "_targets",
      script = "_targets.R"
    )
  )
}

status_of <- function(result, check) result$status[result$check == check]
detail_of <- function(result, check) result$detail[result$check == check][[1]]

test_that("the untouched fixture passes all nine checks", {
  skip_ledger_fixture()
  local_engine()
  result <- audit_copy(copy_fixture())
  expect_identical(result$check, paste0("C", 1:9))
  expect_identical(
    result$status,
    rep("PASS", 9),
    info = paste(unlist(result$detail), collapse = "; ")
  )
  expect_identical(attr(result, "verdict"), "PASS")
})

test_that("C4 fails on an errored target; the unavailable report fails C8, not a stop", {
  skip_ledger_fixture()
  local_engine()
  result <- audit_copy(copy_fixture(fail = TRUE))
  expect_identical(status_of(result, "C4"), "FAIL")
  expect_match(detail_of(result, "C4"), "values: errored", all = FALSE)
  expect_identical(status_of(result, "C8"), "FAIL")
  expect_identical(
    detail_of(result, "C8"),
    "evidence: reportable target not available"
  )
  expect_identical(attr(result, "verdict"), "FAIL")
})

test_that("C5 fails when an input or a document changed", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  cat(
    "13\n",
    file = file.path(proj, "data", "raw", "input values.csv"),
    append = TRUE
  )
  expect_match(
    detail_of(audit_copy(proj), "C5"),
    "input values.csv",
    all = FALSE
  )
  proj2 <- copy_fixture()
  cat("# edited\n", file = file.path(proj2, "decisions.yml"), append = TRUE)
  expect_identical(status_of(audit_copy(proj2), "C5"), "FAIL")
})

test_that("C6 fails for a decision linked to a missing target, and is not evaluated without links", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$links[[3]]$target <- "no_such_target"
    l
  })
  result <- audit_copy(proj)
  expect_identical(status_of(result, "C6"), "FAIL")
  expect_match(detail_of(result, "C6"), "D2", all = FALSE)
  proj2 <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj2), function(l) {
    l$links <- list()
    l
  })
  result2 <- audit_copy(proj2)
  expect_identical(status_of(result2, "C6"), "NOT EVALUATED")
  expect_identical(attr(result2, "verdict"), "INCOMPLETE")
})

test_that("C7 fails when a record was edited, and is not evaluated without records", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  f <- file.path(proj, "output", "record.html")
  writeLines(
    sub(
      "\"sha\":\"[0-9a-f]+\"",
      paste0("\"sha\":\"", strrep("1", 40), "\""),
      readLines(f)
    ),
    f
  )
  expect_identical(status_of(audit_copy(proj), "C7"), "FAIL")
  proj2 <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj2), function(l) {
    l$records <- list()
    l
  })
  expect_identical(status_of(audit_copy(proj2), "C7"), "NOT EVALUATED")
})

test_that("C8 fails when the ledger's provenance disagrees with the report's", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$provenance[[1]]$function_name <- "other_function"
    l
  })
  expect_identical(status_of(audit_copy(proj), "C8"), "FAIL")
})

test_that("C8 fails for missing provenance and for a number printed without it", {
  env <- source_user_code(c(
    "build <- function(x) {",
    "  r <- dctools::create_report()",
    "  dctools::add_line(r, \"n = \", dctools::record_count(r, \"n\", length(x)))",
    "  dctools::add_line(r, \"max = \", max(x))",
    "  r",
    "}"
  ))
  report <- env$build(c(31, 64))
  ledger <- list(
    provenance = lapply(report$provenance, function(p) {
      c(list(report = "ev"), p)
    })
  )
  result <- .check_provenance(ledger, list(ev = report))
  expect_identical(result$status, "FAIL")
  expect_match(result$detail[[1]], "no provenance", all = FALSE)
  expect_false(any(grepl("64", result$detail[[1]])))

  r2 <- env$build(c(1, 2))
  r2$unprovenanced <- list()
  r2$provenance$n$function_name <- NA_character_
  r2$provenance$n$target <- NA_character_
  result2 <- .check_provenance(
    list(provenance = list(c(list(report = "ev2"), r2$provenance$n))),
    list(ev2 = r2)
  )
  expect_identical(result2$status, "FAIL")
  expect_identical(result2$detail[[1]], "ev2:n: missing: function_name, target")
})

test_that("C9 fails when dctools was not installed from a pushed commit", {
  skip_ledger_fixture()
  local_engine(remote_sha = NA_character_)
  result <- audit_copy(copy_fixture())
  expect_identical(status_of(result, "C9"), "FAIL")
  expect_match(detail_of(result, "C9"), "same dctools", all = FALSE)
})

test_that(".verdict: all PASS passes, any FAIL fails, otherwise incomplete", {
  expect_identical(.verdict(c("PASS", "PASS")), "PASS")
  expect_identical(.verdict(c("PASS", "NOT EVALUATED", "FAIL")), "FAIL")
  expect_identical(.verdict(c("PASS", "NOT EVALUATED")), "INCOMPLETE")
})

# Rewrites the record's stamp and re-seals the ledger's record hash, so only
# the stamp's content differs from the untouched fixture.
restamp_record <- function(proj, fn) {
  f <- file.path(proj, "output", "record.html")
  lines <- readLines(f)
  i <- grep("<!-- dctools-stamp ", lines, fixed = TRUE)
  stamp <- jsonlite::fromJSON(
    sub("^.*<!-- dctools-stamp (\\{.*\\}) -->.*$", "\\1", lines[i]),
    simplifyVector = FALSE
  )
  json <- jsonlite::toJSON(
    fn(stamp),
    auto_unbox = TRUE,
    null = "null",
    na = "null"
  )
  lines[i] <- paste0("<!-- dctools-stamp ", json, " -->")
  writeLines(lines, f)
  sha <- digest::digest(f, algo = "sha256", file = TRUE)
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$records[[1]]$sha256 <- sha
    l
  })
}

test_that("C7 fails a stamp that names no objects", {
  skip_ledger_fixture()
  local_engine()
  for (empty in list(NULL, setNames(list(), character(0)))) {
    proj <- copy_fixture()
    restamp_record(proj, function(s) {
      s["objects"] <- list(empty)
      if (is.null(empty)) {
        s$objects <- NULL
      }
      s
    })
    result <- audit_copy(proj)
    expect_identical(status_of(result, "C7"), "FAIL")
    expect_match(
      detail_of(result, "C7"),
      "the stamp names no objects",
      all = FALSE
    )
  }
})

test_that("C7 fails a stamp with no run id, no commit, or a null object hash", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  restamp_record(proj, function(s) {
    s$run_id <- NULL
    s
  })
  result <- audit_copy(proj)
  expect_identical(status_of(result, "C7"), "FAIL")
  expect_match(detail_of(result, "C7"), "the stamp has no run id", all = FALSE)

  # A ledger with no run id stops audit_run() before any check, so C7 is
  # called directly: a missing run id on both sides is not a match.
  proj2 <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj2), function(l) {
    l$run$run_id <- NULL
    l
  })
  restamp_record(proj2, function(s) {
    s$run_id <- NULL
    s
  })
  ledger2 <- jsonlite::read_json(
    fixture_ledger_path(proj2),
    simplifyVector = FALSE
  )
  c7 <- withr::with_dir(proj2, {
    .check_records(
      ledger2,
      "_targets",
      .load_reportable("_targets", "evidence")
    )
  })
  expect_match(c7$detail[[1]], "the stamp has no run id", all = FALSE)

  proj3 <- copy_fixture()
  restamp_record(proj3, function(s) {
    s$sha <- NULL
    s
  })
  expect_match(
    detail_of(audit_copy(proj3), "C7"),
    "the stamp has no commit",
    all = FALSE
  )

  proj4 <- copy_fixture()
  restamp_record(proj4, function(s) {
    s$objects <- list(evidence = NULL)
    s
  })
  result4 <- audit_copy(proj4)
  expect_identical(status_of(result4, "C7"), "FAIL")
  expect_match(detail_of(result4, "C7"), "has no hash", all = FALSE)
})

test_that("C6 fails a linked target whose status is missing or not a built one", {
  skip_ledger_fixture()
  local_engine()
  for (status in list(NULL, "started")) {
    proj <- copy_fixture()
    edit_ledger(fixture_ledger_path(proj), function(l) {
      for (i in seq_along(l$targets)) {
        if (identical(l$targets[[i]]$name, "evidence")) {
          l$targets[[i]]["status"] <- list(status)
        }
      }
      l
    })
    result <- audit_copy(proj)
    expect_identical(status_of(result, "C6"), "FAIL")
    expect_match(
      detail_of(result, "C6"),
      paste0(
        "evidence was not built in this run \\(status ",
        if (is.null(status)) "none" else status,
        "\\)"
      ),
      all = FALSE
    )
  }
})

test_that("C8 fails for a reportable target that was never built or is mistyped", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$reportable[[2]] <- list(
      name = "evidense",
      object_sha256 = NULL,
      available = FALSE
    )
    l
  })
  result <- audit_copy(proj)
  expect_identical(status_of(result, "C8"), "FAIL")
  expect_true(
    "evidense: reportable target not available" %in% detail_of(result, "C8")
  )
})

test_that("C7 fails a stamp naming an object that is not a reportable report", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  # The record also reads `values`, at its correct hash, which no report
  # vouches for.
  values_sha <- .sha256_file(file.path(proj, "_targets", "objects", "values"))
  restamp_record(proj, function(s) {
    s$objects$values <- values_sha
    s
  })
  result <- audit_copy(proj)
  expect_identical(status_of(result, "C7"), "FAIL")
  expect_match(
    detail_of(result, "C7"),
    "values is not a reportable report",
    all = FALSE
  )

  proj2 <- copy_fixture()
  restamp_record(proj2, function(s) {
    s$objects <- "not a named list"
    s
  })
  expect_match(
    detail_of(audit_copy(proj2), "C7"),
    "the stamp names no objects",
    all = FALSE
  )
})

test_that("C7 fails, not crashes, on a record whose stamp is not valid JSON", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  f <- file.path(proj, "output", "record.html")
  writeLines(
    sub(
      "<!-- dctools-stamp \\{.*\\} -->",
      "<!-- dctools-stamp {not json} -->",
      readLines(f)
    ),
    f
  )
  sha <- .sha256_file(f)
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$records[[1]]$sha256 <- sha
    l
  })
  result <- audit_copy(proj)
  expect_identical(status_of(result, "C7"), "FAIL")
  expect_match(detail_of(result, "C7"), "the stamp has no run id", all = FALSE)
})

test_that("audit_run refuses a ledger whose run id is not YYYYMMDD-HHMMSS", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$run$run_id <- "../../evil"
    l
  })
  expect_error(audit_copy(proj), class = "dctools_audit_run_id_error")
  expect_identical(
    list.files(file.path(proj, "docs", "runs"), recursive = TRUE),
    paste0(fixture_run_id, ".json")
  )
  expect_false(file.exists(file.path(proj, "evil.md")))
})
