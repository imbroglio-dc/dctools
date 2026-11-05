export_copy <- function(proj, edit = NULL) {
  if (!is.null(edit)) {
    edit_ledger(fixture_ledger_path(proj), edit)
  }
  result <- audit_copy(proj)
  withr::with_dir(proj, export_run_evidence(
    fixture_ledger_path("."),
    "evidence/runs/run",
    result = result,
    store = "_targets",
    script = "_targets.R"
  ))
}

exported_text <- function(proj) {
  paste(
    readLines(file.path(proj, "evidence", "runs", "run", "ledger.json")),
    collapse = "\n"
  )
}

test_that("the export keeps file digests and source strings, not object or dependency hashes", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  export_copy(proj)
  out <- file.path(proj, "evidence", "runs", "run")
  expect_setequal(list.files(out), c("ledger.json", "audit.md", "provenance.md"))
  l <- jsonlite::read_json(file.path(out, "ledger.json"))
  txt <- exported_text(proj)
  for (field in c("object_sha256", "\"data\"", "\"depend\"", "library_paths", "\"dirty_files\"", "user:secret")) {
    expect_false(grepl(field, txt, fixed = TRUE), info = field)
  }
  expect_identical(l$export$schema_version, 1L)
  expect_identical(l$inputs[[1]]$path, "data/raw/input values.csv")
  expect_match(l$inputs[[1]]$sha256, "^[0-9a-f]{64}$")
  expect_identical(l$records[[1]]$path, "output/record.html")
  expect_setequal(vapply(l$targets, function(t) t$name, ""), c("input_file", "values", "evidence", "record_file"))
  expect_setequal(vapply(l$provenance, function(p) p$id, ""), c("n_values", "n_large"))
  # D2 is linked but appears in no declared document.
  expect_identical(vapply(l$links, function(x) x$decision_id, ""), c("D1", "D1"))
  expect_identical(l$export$withheld$links, 1L)
})

test_that("data-derived names, undeclared paths and unknown fields are withheld", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  export_copy(proj, function(l) {
    branch <- l$targets[[1]]
    branch$name <- "values_8f3dd8ad0244cf0e"
    l$targets <- c(l$targets, list(branch))
    l$provenance[[1]]$id <- "n_site_SiteZ"
    l$inputs <- c(l$inputs, list(list(path = "data/raw/pt_12345.csv", sha256 = strrep("a", 64))))
    l$code$dirty_files <- list("data/pt_12345_notes.txt")
    l$outdated <- list("values_8f3dd8ad0244cf0e")
    l$secret_field <- "pt_12345"
    l
  })
  txt <- exported_text(proj)
  expect_false(grepl("8f3dd8ad|SiteZ|12345|secret_field", txt), info = txt)
  l <- jsonlite::read_json(file.path(proj, "evidence", "runs", "run", "ledger.json"))
  w <- l$export$withheld
  expect_identical(w$targets, 1L)
  expect_identical(w$provenance, 1L)
  expect_identical(w$paths, 1L)
  expect_identical(w$names, 1L)
  expect_identical(l$code$n_dirty_files, 1L)
  # The undeclared input keeps its digest (raw inputs may be digested), not its name.
  expect_true(any(vapply(l$inputs, function(i) is.null(i$path) && identical(i$sha256, strrep("a", 64)), logical(1))))
  pages <- paste(c(
    readLines(file.path(proj, "evidence", "runs", "run", "audit.md")),
    readLines(file.path(proj, "evidence", "runs", "run", "provenance.md"))
  ), collapse = "\n")
  expect_false(grepl("8f3dd8ad|SiteZ|12345", pages))
})

test_that("the exported audit page has statuses but no check details", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  export_copy(proj, function(l) {
    l$input_stability[[1]]$sha256_before <- strrep("0", 64)
    l
  })
  page <- readLines(file.path(proj, "evidence", "runs", "run", "audit.md"))
  expect_true("| C10 | Input stability | FAIL | 2 | 1 |" %in% page)
  expect_false(any(grepl("changed during the run", page)))
  expect_true(any(grepl("Check details stay in the private audit page", page)))
  prov <- readLines(file.path(proj, "evidence", "runs", "run", "provenance.md"))
  expect_true(any(grepl("`evidence` / `n_values` = `12`", prov, fixed = TRUE)))
})
