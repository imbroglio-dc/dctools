# A committed copy of the ledger fixture project with a runner shim that
# writes and audits a ledger. Under load_all, dctools has no RemoteSha, so C9
# fails and a clean run exits 3: that is the expected, correct outcome here.
make_ledger_runner_project <- function(env = parent.frame()) {
  proj <- copy_fixture(env = env)
  unlink(file.path(proj, c("_targets", "docs", "output")), recursive = TRUE)
  dir.create(file.path(proj, "code", "pipeline"), recursive = TRUE)
  writeLines(
    c(
      load_dctools_line,
      "quit(status = run_targets_safe(",
      "  commandArgs(trailingOnly = TRUE),",
      "  ledger = list(",
      "    reportable = 'evidence',",
      "    links = data.frame(decision_id = 'D1', decision_status = 'decided',",
      "                       target = 'values', role = 'args'),",
      "    documents = 'decisions.yml',",
      "    records = 'output/record.html'",
      "  )",
      "), save = 'no')"
    ),
    file.path(proj, "code", "pipeline", "run_pipeline_safe.R")
  )
  system2("git", c("-C", proj, "add", "-A"), stdout = TRUE)
  system2("git", c("-C", proj, "commit", "-q", "-m", "runner"), stdout = TRUE)
  proj
}

test_that("a ledgered run prints the audit block and exits 3 when only C9 fails", {
  skip_ledger_fixture()
  proj <- make_ledger_runner_project()
  res <- run_rscript(proj, "code/pipeline/run_pipeline_safe.R")
  lines <- strsplit(res$stdout, "\n")[[1]]
  expect_identical(res$status, 3L, info = res$stdout)
  expect_identical(res$stderr, "")
  expect_true("== audit ==" %in% lines, info = res$stdout)
  for (check in c(
    "C1 Code: PASS",
    "C2 Ledger matches store: PASS",
    "C5 Inputs: PASS",
    "C7 Records: PASS",
    "C8 Provenance: PASS",
    "C9 Engine: FAIL"
  )) {
    expect_true(check %in% lines, info = res$stdout)
  }
  expect_true("verdict: FAIL" %in% lines)
  expect_match(res$stdout, "ledger: docs/runs/[0-9]{8}-[0-9]{6}\\.json")
  runs <- list.files(file.path(proj, "docs", "runs"))
  expect_length(grep("\\.json$", runs), 1L)
  expect_length(grep("[0-9]\\.md$", runs), 1L)
  expect_length(grep("\\.provenance\\.md$", runs), 1L)
})

test_that("a dirty working tree is refused before the pipeline runs", {
  skip_ledger_fixture()
  proj <- make_ledger_runner_project()
  writeLines("scratch", file.path(proj, "R", "untracked.R"))
  res <- run_rscript(proj, "code/pipeline/run_pipeline_safe.R")
  expect_identical(res$status, 2L)
  expect_identical(
    res$stdout,
    "runner failed: dctools_runner_dirty_tree_error\n"
  )
  expect_false(dir.exists(file.path(proj, "_targets")))
})

test_that(".check_ledger_config fills defaults and rejects unknown elements", {
  cfg <- .check_ledger_config(list(reportable = "x"))
  expect_identical(cfg$dir, "docs/runs")
  expect_identical(cfg$reportable, "x")
  expect_error(
    .check_ledger_config(list(nope = 1)),
    class = "dctools_runner_usage_error"
  )
  expect_error(
    .check_ledger_config("docs"),
    class = "dctools_runner_usage_error"
  )
})
