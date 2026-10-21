# A small committed targets project with a run ledger, for the ledger and
# audit tests. Built once per session (one plain, one with a failing target)
# and copied per test so tests can corrupt their copy freely.

fixture_run_id <- "20260101-000000"
.fixture_cache <- new.env()

local_engine <- function(remote_sha = "abc123", env = parent.frame()) {
  testthat::local_mocked_bindings(
    .dctools_engine = function() {
      list(version = "9.9.9", remote_sha = remote_sha)
    },
    .env = env
  )
}

fixture_links <- function() {
  data.frame(
    decision_id = c("D1", "D1", "D2"),
    decision_status = c("decided", "decided", "open"),
    target = c("values", "evidence", "evidence"),
    role = c("args", "evidence", "evidence"),
    stringsAsFactors = FALSE
  )
}

.build_ledger_fixture <- function(fail) {
  proj <- file.path(tempfile("ledger-fixture-"), "project")
  dir.create(file.path(proj, "R"), recursive = TRUE)
  dir.create(file.path(proj, "data", "raw"), recursive = TRUE)
  writeLines(c("_targets/", "data/", "output/"), file.path(proj, ".gitignore"))
  writeLines(
    c("decisions:", "  - id: D1", "    status: decided"),
    file.path(proj, "decisions.yml")
  )
  write.csv(
    data.frame(v = 1:12),
    file.path(proj, "data", "raw", "input values.csv"),
    row.names = FALSE
  )
  writeLines(
    c(
      "build_evidence <- function(values) {",
      "  r <- dctools::create_report()",
      "  dctools::run_section(r, \"Counts\", {",
      "    dctools::add_line(r, \"values: \", dctools::record_count(r, \"n_values\", length(values)))",
      "    dctools::add_line(r, \"large: \", dctools::record_count(r, \"n_large\", sum(values > 2)))",
      "  })",
      "  r",
      "}"
    ),
    file.path(proj, "R", "evidence.R")
  )
  writeLines(
    c(
      "library(targets)",
      load_dctools_line,
      "for (f in list.files('R', full.names = TRUE)) source(f, keep.source = TRUE)",
      "fail <- identical(Sys.getenv('FIXTURE_FAIL'), '1')",
      "list(",
      "  tar_target(input_file, 'data/raw/input values.csv', format = 'file'),",
      "  tar_target(values, if (fail) stop('synthetic failure') else utils::read.csv(input_file)$v),",
      "  tar_target(evidence, build_evidence(values)),",
      "  tar_target(record_file, {",
      "    evidence",
      "    dir.create('output', showWarnings = FALSE)",
      "    writeLines(utils::capture.output(dctools::stamp_record('evidence', store = '_targets')),",
      "      'output/record.html')",
      "    'output/record.html'",
      "  }, format = 'file')",
      ")"
    ),
    file.path(proj, "_targets.R")
  )
  writeLines("targets::tar_make(reporter = 'silent')", file.path(proj, "run.R"))
  git <- function(...) {
    system2("git", c("-C", proj, ...), stdout = TRUE, stderr = TRUE)
  }
  git("init", "-q")
  git("config", "user.email", "test@example.com")
  git("config", "user.name", "test")
  git("remote", "add", "origin", "https://user:secret@example.com/o/r.git")
  git("add", "-A")
  git("commit", "-q", "-m", "fixture")
  res <- run_rscript(
    proj,
    "run.R",
    env = c(
      DCTOOLS_RUN_ID = fixture_run_id,
      FIXTURE_FAIL = if (fail) "1" else "0"
    )
  )
  if (!fail && res$status != 0L) {
    stop("fixture pipeline failed: ", res$stderr)
  }
  # tar_network() and tar_outdated() source _targets.R in a child process,
  # which loads dctools through DCTOOLS_TEST_SRC.
  withr::local_envvar(DCTOOLS_TEST_SRC = dctools_src())
  testthat::with_mocked_bindings(
    withr::with_dir(
      proj,
      write_run_ledger(
        path = "docs/runs",
        run_id = fixture_run_id,
        reportable = "evidence",
        links = fixture_links(),
        documents = "decisions.yml",
        records = if (fail) character(0) else "output/record.html",
        store = "_targets",
        script = "_targets.R",
        exit_code = if (fail) 1L else 0L
      )
    ),
    .dctools_engine = function() list(version = "9.9.9", remote_sha = "abc123")
  )
  proj
}

ledger_fixture <- function(fail = FALSE) {
  key <- if (fail) "fail" else "pass"
  if (is.null(.fixture_cache[[key]])) {
    .fixture_cache[[key]] <- .build_ledger_fixture(fail)
  }
  .fixture_cache[[key]]
}

# Also sets DCTOOLS_TEST_SRC for the calling test: the audit's targets calls
# source _targets.R in a child process that must load this dctools.
copy_fixture <- function(fail = FALSE, env = parent.frame()) {
  withr::local_envvar(DCTOOLS_TEST_SRC = dctools_src(), .local_envir = env)
  src <- ledger_fixture(fail)
  dest <- file.path(withr::local_tempdir(.local_envir = env), "project")
  fs::dir_copy(src, dest)
  dest
}

skip_ledger_fixture <- function() {
  skip_subprocess(c("processx", "targets", "callr", "jsonlite", "digest", "fs"))
}

edit_ledger <- function(path, fn) {
  ledger <- jsonlite::read_json(path, simplifyVector = FALSE)
  jsonlite::write_json(
    fn(ledger),
    path,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null",
    digits = NA
  )
}

fixture_ledger_path <- function(proj) {
  file.path(proj, "docs", "runs", paste0(fixture_run_id, ".json"))
}
