fixture_ledger <- function(proj) {
  jsonlite::read_json(fixture_ledger_path(proj), simplifyVector = FALSE)
}

test_that(".literal_paths reads literal file-target commands only", {
  expect_identical(.literal_paths("\"data/raw/a.csv\""), "data/raw/a.csv")
  expect_identical(.literal_paths("c(\"a.csv\", \"b.csv\")"), c("a.csv", "b.csv"))
  expect_identical(.literal_paths("file.path(\"data\", \"a.csv\")"), character(0))
  expect_identical(.literal_paths("{"), character(0))
})

test_that(".files_under lists data files, not README notes", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "raw", "sub"), recursive = TRUE)
  writeLines("x", file.path(dir, "raw", "a.csv"))
  writeLines("x", file.path(dir, "raw", "sub", "b.csv"))
  writeLines("notes", file.path(dir, "raw", "README.md"))
  withr::with_dir(dir, {
    expect_identical(.files_under("raw/"), c("raw/a.csv", "raw/sub/b.csv"))
    expect_identical(.files_under("missing"), character(0))
  })
})

test_that(".stability_block numbers undeclared files and drops their names", {
  dir <- withr::local_tempdir()
  withr::with_dir(dir, {
    writeLines("1", "in.csv")
    writeLines("2", "pt_12345_labs.csv")
    before <- .hash_paths(c("in.csv", "pt_12345_labs.csv"))
    block <- .stability_block(before, declared = "in.csv")
  })
  expect_identical(block[[1]]$path, "in.csv")
  expect_true(block[[1]]$declared)
  expect_identical(block[[1]]$sha256_before, block[[1]]$sha256_after)
  expect_true(is.na(block[[2]]$path))
  expect_identical(block[[2]]$undeclared_index, 1L)
  expect_false(grepl("12345", paste(unlist(block), collapse = " ")))
  expect_null(.stability_block(NULL, "in.csv"))
})

test_that("the ledger records environment, input stability and built targets", {
  skip_ledger_fixture()
  l <- fixture_ledger(ledger_fixture())
  expect_identical(l$environment$computational$packages[[1]]$package, "jsonlite")
  expect_true(length(l$environment$full$installed) > 0L)
  paths <- vapply(l$input_stability, function(e) e$path, "")
  expect_setequal(paths, c("decisions.yml", "data/raw/input values.csv"))
  for (e in l$input_stability) {
    expect_identical(e$sha256_before, e$sha256_after)
  }
  for (t in l$targets) {
    expect_true(t$built)
    expect_identical(t$origin_run_id, fixture_run_id)
  }
})

prior_target <- function(...) {
  utils::modifyList(
    list(name = "fit", command = "c1", depend = "d1", data = "h1", status = "completed"),
    list(...)
  )
}

test_that("a reused target's origin is the earlier run that built it, else unknown", {
  priors <- list(
    list(run = list(run_id = "20260102-000000"), targets = list(prior_target(status = "skipped", origin_run_id = "20251231-000000"))),
    list(run = list(run_id = "20260101-000000"), targets = list(prior_target()))
  )
  now <- list(
    prior_target(status = "skipped"),
    prior_target(name = "other", status = "skipped"),
    prior_target(name = "new", status = "completed"),
    prior_target(name = "bad", status = "errored")
  )
  out <- .add_origins(now, "20260103-000000", priors)
  expect_identical(out[[1]]$origin_run_id, "20251231-000000")
  expect_false(out[[1]]$built)
  expect_true(is.na(out[[2]]$origin_run_id))
  expect_identical(out[[3]]$origin_run_id, "20260103-000000")
  expect_true(out[[3]]$built)
  expect_true(is.na(out[[4]]$origin_run_id))
  # Different data: not the same build, so not its origin.
  changed <- .add_origins(list(prior_target(status = "skipped", data = "h2")), "20260103-000000", priors[2])
  expect_true(is.na(changed[[1]]$origin_run_id))
  # A v1 ledger names no origin; a build in it is the origin.
  v1 <- .add_origins(list(prior_target(status = "skipped")), "20260103-000000", priors[2])
  expect_identical(v1[[1]]$origin_run_id, "20260101-000000")
})

test_that(".prior_ledgers reads earlier ledgers only, newest first", {
  dir <- withr::local_tempdir()
  for (id in c("20260101-000000", "20260103-000000", "20260105-000000")) {
    jsonlite::write_json(list(run = list(run_id = id)), file.path(dir, paste0(id, ".json")), auto_unbox = TRUE)
  }
  writeLines("not a ledger", file.path(dir, "20260101-000000.md"))
  ids <- vapply(.prior_ledgers(dir, "20260104-000000"), function(l) l$run$run_id[[1]], "")
  expect_identical(ids, c("20260103-000000", "20260101-000000"))
})

# Planted defects: each must fail for the expected reason.

test_that("C10 fails when an input changed during the run", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$input_stability[[1]]$sha256_before <- strrep("0", 64)
    l
  })
  result <- audit_copy(proj)
  expect_identical(status_of(result, "C10"), "FAIL")
  expect_match(detail_of(result, "C10"), "changed during the run")
})

test_that("C10 fails an input not hashed before the run and an undeclared file", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$input_stability[[1]]$sha256_before <- NA
    l$input_stability <- c(l$input_stability, list(list(
      path = NA, declared = FALSE, undeclared_index = 1L,
      sha256_before = strrep("a", 64), sha256_after = strrep("a", 64)
    )))
    l
  })
  d <- detail_of(audit_copy(proj), "C10")
  expect_true(any(grepl("not hashed before the run", d)))
  expect_true(any(grepl("undeclared input file #1: undeclared", d)))
})

test_that("C10 and C11 are not evaluated for a ledger without them", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$input_stability <- NULL
    l$environment <- NULL
    l
  })
  result <- audit_copy(proj)
  expect_identical(status_of(result, "C10"), "NOT EVALUATED")
  expect_identical(status_of(result, "C11"), "NOT EVALUATED")
  expect_identical(attr(result, "verdict"), "INCOMPLETE")
})

test_that("C11 fails on a package version, commit or R version that differs from renv.lock", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  write_fixture_lock(proj, version = "0.0.1")
  d <- detail_of(audit_copy(proj), "C11")
  expect_true(any(grepl("jsonlite: installed .*, renv.lock has 0.0.1", d)))
  expect_true(any(grepl("renv.lock differs from the one the run recorded", d)))

  proj <- copy_fixture()
  lock <- jsonlite::read_json(file.path(proj, "renv.lock"))
  lock$Packages$jsonlite$RemoteSha <- "deadbeef"
  jsonlite::write_json(lock, file.path(proj, "renv.lock"), auto_unbox = TRUE)
  expect_true(any(grepl("different commit", detail_of(audit_copy(proj), "C11"))))

  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$environment$computational$r_version <- "3.0.0"
    l
  })
  expect_true(any(grepl("ran under R 3.0.0", detail_of(audit_copy(proj), "C11"))))
})

test_that("C11 is not evaluated without renv.lock", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  unlink(file.path(proj, "renv.lock"))
  expect_identical(status_of(audit_copy(proj), "C11"), "NOT EVALUATED")
})

test_that("C2 fails a target labelled built that the store did not build this run", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$targets[[1]]$origin_run_id <- "20251201-000000"
    l
  })
  result <- audit_copy(proj)
  expect_identical(status_of(result, "C2"), "FAIL")
  expect_match(detail_of(result, "C2"), "differs: built")
})

test_that(".files_under with no directories is empty", {
  expect_identical(.files_under(character(0)), character(0))
})
