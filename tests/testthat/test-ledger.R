read_fixture_ledger <- function(proj) {
  jsonlite::read_json(fixture_ledger_path(proj), simplifyVector = FALSE)
}

by_name <- function(xs, key = "name") {
  stats::setNames(xs, vapply(xs, function(x) x[[key]], ""))
}

test_that("the ledger records code, inputs and documents, without credentials", {
  skip_ledger_fixture()
  proj <- ledger_fixture()
  l <- read_fixture_ledger(proj)
  expect_identical(l$schema_version, 1L)
  expect_identical(l$run$run_id, fixture_run_id)
  expect_identical(l$code$sha, .git_head(proj))
  expect_true(l$code$clean)
  expect_identical(l$code$remote, "https://example.com/o/r.git")
  expect_identical(l$code$dctools_remote_sha, "abc123")
  inputs <- by_name(l$inputs, "path")
  expect_identical(
    inputs[["data/raw/input values.csv"]]$sha256,
    .sha256_file(file.path(proj, "data/raw/input values.csv"))
  )
  expect_identical(l$documents[[1]]$path, "decisions.yml")
  expect_identical(
    l$documents[[1]]$sha256,
    .sha256_file(file.path(proj, "decisions.yml"))
  )
  expect_false(grepl(
    "secret",
    paste(readLines(fixture_ledger_path(proj)), collapse = "\n")
  ))
})

test_that("the ledger records targets, their upstream targets and function spans", {
  skip_ledger_fixture()
  l <- read_fixture_ledger(ledger_fixture())
  t <- by_name(l$targets)
  expect_setequal(
    names(t),
    c("input_file", "values", "evidence", "record_file")
  )
  expect_identical(unlist(t$evidence$upstream), "values")
  fn <- t$evidence$functions[[1]]
  expect_identical(fn$name, "build_evidence")
  expect_identical(fn$file, "R/evidence.R")
  expect_identical(c(fn$line_start, fn$line_end), c(1L, 8L))
  expect_match(t$evidence$object_sha256, "^[0-9a-f]{64}$")
  expect_identical(t$evidence$status, "completed")
  expect_length(l$outdated, 0L)
})

test_that("the ledger records links, reportable targets, records and provenance, but no values", {
  skip_ledger_fixture()
  proj <- ledger_fixture()
  l <- read_fixture_ledger(proj)
  expect_length(l$links, 3L)
  expect_identical(l$reportable[[1]]$name, "evidence")
  expect_true(l$reportable[[1]]$available)
  expect_identical(l$records[[1]]$path, "output/record.html")
  expect_identical(l$records[[1]]$stamps[[1]]$run_id, fixture_run_id)
  p <- by_name(l$provenance, "id")
  expect_setequal(names(p), c("n_values", "n_large"))
  expect_identical(p$n_values$file, "R/evidence.R")
  expect_identical(p$n_values$line_start, 4L)
  expect_identical(p$n_values$function_name, "build_evidence")
  expect_identical(p$n_values$target, "evidence")
  expect_length(l$unprovenanced, 0L)
  txt <- paste(readLines(fixture_ledger_path(proj)), collapse = "\n")
  expect_false(grepl("\"value\"", txt))
})

test_that(".spans_in_lines finds top-level function definitions only", {
  spans <- .spans_in_lines(
    c(
      "f <- function(x) {",
      "  g <- function() 1",
      "  x",
      "}",
      "h = function() NULL",
      "y <- 3"
    ),
    "R/a.R"
  )
  expect_identical(spans$name, c("f", "h"))
  expect_identical(spans$line_start, c(1L, 5L))
  expect_identical(spans$line_end, c(4L, 5L))
  expect_identical(nrow(.spans_in_lines("not ( valid", "R/b.R")), 0L)
})

test_that("a non-report or unmasked reportable target stops before anything is written", {
  fake <- function(value) function(name) value
  expect_error(
    .load_reportable("store", "x", read = fake(1:3)),
    class = "dctools_audit_unsafe_error"
  )
  expect_error(
    .load_reportable(
      "store",
      "x",
      read = fake(create_report(hide_small_counts = FALSE))
    ),
    class = "dctools_audit_unsafe_error"
  )
  expect_identical(.load_reportable("store", "x", read = fake(NULL)), list())
})

test_that("write_run_ledger writes nothing when a reportable target is unsafe", {
  skip_ledger_fixture()
  proj <- copy_fixture()
  local_engine()
  withr::local_dir(proj)
  expect_error(
    write_run_ledger(
      "docs/new",
      "20260102-000000",
      reportable = "values",
      store = "_targets",
      script = "_targets.R"
    ),
    class = "dctools_audit_unsafe_error"
  )
  expect_false(dir.exists("docs/new"))
})

test_that("a failed run still gets a ledger; the errored reportable target is unavailable", {
  skip_ledger_fixture()
  l <- read_fixture_ledger(ledger_fixture(fail = TRUE))
  t <- by_name(l$targets)
  expect_identical(t$values$status, "errored")
  expect_false(l$reportable[[1]]$available)
  expect_length(l$provenance, 0L)
})

# All leaf values of a parsed ledger, with the names on the way down.
.leaves <- function(x, path = character(0)) {
  if (is.list(x)) {
    nms <- names(x)
    out <- list()
    for (i in seq_along(x)) {
      key <- if (!is.null(nms) && nzchar(nms[[i]])) nms[[i]] else NULL
      out <- c(out, .leaves(x[[i]], c(path, key)))
    }
    out
  } else {
    list(list(key = if (length(path)) path[[length(path)]] else "", value = x))
  }
}

test_that("no reported count value and no error text reaches the ledger", {
  skip_ledger_fixture()
  l <- read_fixture_ledger(ledger_fixture())
  numeric_ok <- c(
    "line_start",
    "line_end",
    "function_line_start",
    "function_line_end",
    "exit_code",
    "schema_version",
    "n_definitions"
  )
  for (leaf in .leaves(l)) {
    if (is.numeric(leaf$value) && !(leaf$key %in% numeric_ok)) {
      expect_false(any(leaf$value %in% c(12, 10)), info = leaf$key)
    }
  }
  txt <- paste(
    readLines(fixture_ledger_path(ledger_fixture(fail = TRUE))),
    collapse = "\n"
  )
  expect_false(grepl("synthetic", txt))
  expect_true(grepl('"provenance": \\[\\]', txt))
  expect_true(grepl('"records": \\[\\]', txt))
})

test_that("a tracked file deleted from the working tree does not abort the ledger", {
  skip_ledger_fixture()
  proj <- copy_fixture()
  local_engine()
  withr::local_dir(proj)
  writeLines("extra <- function() 1", "R/extra.R")
  system2("git", c("add", "-A"), stdout = TRUE)
  system2("git", c("commit", "-q", "-m", "extra"), stdout = TRUE)
  file.remove("R/extra.R")
  out <- write_run_ledger(
    "docs/new",
    "20260102-000000",
    reportable = "evidence",
    store = "_targets",
    script = "_targets.R"
  )
  l <- jsonlite::read_json(out, simplifyVector = FALSE)
  expect_false(l$code$clean)
})

test_that("only the four stamp fields are recorded", {
  skip_ledger_fixture()
  proj <- copy_fixture()
  local_engine()
  withr::local_dir(proj)
  html <- readLines("output/record.html")
  html <- sub('\\}\\} -->', '}, "note": "x"} -->', html)
  writeLines(html, "output/record2.html")
  expect_match(paste(html, collapse = ""), "note")
  out <- write_run_ledger(
    "docs/new",
    "20260102-000000",
    reportable = "evidence",
    records = "output/record2.html",
    store = "_targets",
    script = "_targets.R"
  )
  l <- jsonlite::read_json(out, simplifyVector = FALSE)
  stamp <- l$records[[1]]$stamps[[1]]
  expect_setequal(
    names(stamp),
    c("run_id", "sha", "dctools_version", "objects")
  )
  expect_identical(stamp$run_id, fixture_run_id)
  expect_match(unlist(stamp$objects), "^[0-9a-f]{64}$")
})
