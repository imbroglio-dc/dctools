# Pure helpers -------------------------------------------------------------------

test_that(".mask_count masks 1 to below-1 only", {
  expect_identical(
    .mask_count(c(0, 1, 4, 5, 12)),
    c("0", "<5", "<5", "5", "12")
  )
  expect_identical(.mask_count(c(4, 10, 11), below = 11), c("<11", "<11", "11"))
})

test_that(".parse_runner_args accepts --names identifiers only", {
  expect_identical(.parse_runner_args(character(0)), character(0))
  expect_identical(.parse_runner_args(c("--names", "a", "b.c")), c("a", "b.c"))
  expect_error(.parse_runner_args("--names"), class = "dctools_runner_usage_error")
  expect_error(.parse_runner_args(c("a", "b")), class = "dctools_runner_usage_error")
  expect_error(
    .parse_runner_args(c("--names", "x;y")),
    class = "dctools_runner_usage_error"
  )
})

progress_df <- function(name, progress) {
  data.frame(name = name, progress = progress, stringsAsFactors = FALSE)
}

test_that(".format_run_summary prints codes and masked counts, never messages", {
  out <- .format_run_summary(
    progress_df(c("prep", "rec"), c("errored", "skipped")),
    list(list(
      target = "prep",
      status = "error",
      class = list("D5_x", "prep_error"),
      code = "D5_norm",
      counts = list(n_bad = 3, n_ok = 12),
      context = "plate",
      n_warnings = 0,
      message = "row EARLY-1"
    )),
    character(0),
    "data/processed/debug/20260101-000000"
  )
  expect_identical(
    out,
    c(
      "== targets ==",
      "prep: errored",
      "rec: skipped",
      "== errors and warnings (detail in the debug directory) ==",
      "  prep: class=D5_x code=D5_norm n_bad=<5 n_ok=12 warnings: 0",
      "debug directory: data/processed/debug/20260101-000000"
    )
  )
})

test_that(".format_run_summary drops odd names, non-integer counts and bad codes", {
  out <- .format_run_summary(
    progress_df(c("ok", "bad name;rm"), c("built", "built")),
    list(list(
      target = "EARLY-1",
      class = "has space",
      code = "x y",
      counts = list(`a b` = 1, txt = "EARLY", n = 7),
      n_warnings = "lots"
    )),
    character(0),
    "d"
  )
  expect_false(any(grepl("bad name|EARLY|has space|x y|a b", out)))
  expect_true("ok: built" %in% out)
  expect_true("  ?: n=7 warnings: ?" %in% out)
})

test_that(".format_run_summary appends the run status block", {
  out <- .format_run_summary(
    progress_df("s", "built"),
    list(),
    c("-- A --", "line"),
    "d"
  )
  expect_identical(out, c("== targets ==", "s: built", "== run status ==", "-- A --", "line", "debug directory: d"))
})

test_that(".prune_debug_runs keeps the newest N run dirs and ignores other names", {
  root <- withr::local_tempdir()
  runs <- sprintf("2026010%d-000000", 1:5)
  for (r in c(runs, "keep_me")) dir.create(file.path(root, r))
  removed <- .prune_debug_runs(root, keep = 2L)
  expect_identical(removed, runs[1:3])
  expect_setequal(list.files(root), c(runs[4:5], "keep_me"))
})

test_that(".run_status_blocks prints finished status targets in order", {
  progress <- progress_df(c("b_status", "a_status", "c_status"), c("built", "skipped", "errored"))
  objs <- list(a_status = c("a1", "a2"), b_status = "b1")
  read <- function(name) objs[[name]]
  out <- .run_status_blocks(
    progress,
    c(A = "a_status", B = "b_status", C = "c_status"),
    read,
    NULL
  )
  expect_identical(out, c("-- A --", "a1", "a2", "-- B --", "b1"))
})

test_that(".run_status_blocks applies format_status and requires character", {
  progress <- progress_df("s", "built")
  read <- function(name) list(n = 3)
  out <- .run_status_blocks(progress, c(S = "s"), read, function(x) paste("n =", x$n))
  expect_identical(out, c("-- S --", "n = 3"))
  expect_error(
    .run_status_blocks(progress, c(S = "s"), read, NULL),
    class = "dctools_runner_status_error"
  )
})

test_that(".check_status_targets wants identifier names and values", {
  expect_identical(.check_status_targets(character(0)), character(0))
  expect_identical(.check_status_targets(c("x_status")), c(x_status = "x_status"))
  expect_error(.check_status_targets(c(`A B` = "x")), class = "dctools_runner_usage_error")
  expect_error(.check_status_targets(c(A = "x;y")), class = "dctools_runner_usage_error")
})

# In-process failures (no pipeline needed) ---------------------------------------

test_that("bad arguments: exit 2, only the class on stdout, detail in runner.log", {
  skip_if_not_installed("targets")
  skip_if_not_installed("tidyselect")
  skip_if_not_installed("jsonlite")
  proj <- withr::local_tempdir()
  withr::local_dir(proj)
  out <- utils::capture.output(
    status <- run_targets_safe(c("--names", "x;y"), run_id = "20260101-000000")
  )
  expect_identical(status, 2L)
  expect_identical(out, "runner failed: dctools_runner_usage_error")
  log <- readLines(file.path(
    proj,
    "data/processed/debug/20260101-000000/runner.log"
  ))
  expect_true(any(grepl("target names must be identifiers", log)))
  expect_false(any(grepl("x;y", out, fixed = TRUE)))
})

test_that("a debug root outside the private root fails before writing anything", {
  skip_if_not_installed("targets")
  skip_if_not_installed("tidyselect")
  skip_if_not_installed("jsonlite")
  proj <- withr::local_tempdir()
  withr::local_dir(proj)
  out <- utils::capture.output(
    status <- run_targets_safe(debug_root = "output/debug")
  )
  expect_identical(status, 2L)
  expect_identical(out, "runner failed: dctools_unsafe_path_error")
  expect_length(list.files(proj, recursive = TRUE, all.files = TRUE), 0L)
})

test_that("a bad run_id is a runner failure", {
  skip_if_not_installed("targets")
  skip_if_not_installed("tidyselect")
  skip_if_not_installed("jsonlite")
  proj <- withr::local_tempdir()
  withr::local_dir(proj)
  out <- utils::capture.output(status <- run_targets_safe(run_id = "../x"))
  expect_identical(status, 2L)
  expect_identical(out, "runner failed: dctools_runner_usage_error")
})

# End to end on a toy pipeline, through an Rscript shim as a project would ------

skip_end_to_end <- function() {
  skip_on_cran()
  for (p in c("targets", "tidyselect", "jsonlite", "processx", "callr")) {
    skip_if_not_installed(p)
  }
  if (nzchar(dctools_src())) skip_if_not_installed("pkgload")
}

make_toy_project <- function(env = parent.frame()) {
  proj <- withr::local_tempdir(.local_envir = env)
  writeLines(
    c(
      "library(targets)",
      load_dctools_line,
      "fail <- identical(Sys.getenv('TOY_FAIL'), '1')",
      "list(",
      "  tar_target(clean, capture_target_debug({",
      "    message('chatty message EARLY-7'); cat('printed EARLY-8\\n'); 1L",
      "  }, 'clean')),",
      "  tar_target(warned, capture_target_debug({",
      "    warning('warning EARLY-9'); 2L",
      "  }, 'warned')),",
      "  tar_target(prep, {",
      "    clean",
      "    capture_target_debug(if (fail) abort_safe(",
      "      'row EARLY-1 has value 99', code = 'D5_norm',",
      "      counts = list(n_bad = 3L, n_rows = 120L),",
      "      debug = data.frame(id = 'EARLY-1', v = 99)",
      "    ) else 3L, 'prep')",
      "  }),",
      "  tar_target(run_status, c(",
      "    paste0('prep: ', if (fail) 'stopped' else 'completed'),",
      "    'decisions: 4'",
      "  )),",
      "  tar_target(after_prep, prep + 1L)",
      ")"
    ),
    file.path(proj, "_targets.R")
  )
  dir.create(file.path(proj, "code", "pipeline"), recursive = TRUE)
  writeLines(
    c(
      load_dctools_line,
      "quit(status = run_targets_safe(",
      "  commandArgs(trailingOnly = TRUE),",
      "  status_targets = c(TOY = 'run_status')",
      "), save = 'no')"
    ),
    file.path(proj, "code", "pipeline", "run_pipeline_safe.R")
  )
  proj
}

# stdout/stderr with "\r\n" (Windows) normalized to "\n".
run_shim <- function(proj, args = character(0), fail = FALSE) {
  res <- processx::run(
    file.path(R.home("bin"), "Rscript"),
    c("code/pipeline/run_pipeline_safe.R", args),
    wd = proj,
    error_on_status = FALSE,
    env = c(
      "current",
      DCTOOLS_TEST_SRC = dctools_src(),
      TOY_FAIL = if (fail) "1" else "0",
      R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)
    )
  )
  res$stdout <- gsub("\r\n", "\n", res$stdout, fixed = TRUE)
  res$stderr <- gsub("\r\n", "\n", res$stderr, fixed = TRUE)
  res
}

debug_runs <- function(proj) {
  list.dirs(file.path(proj, "data", "processed", "debug"), recursive = FALSE)
}

leaky <- "EARLY-|chatty|printed|value 99|warning EARLY"

test_that("a clean run exits 0 and prints only the allowlist", {
  skip_end_to_end()
  proj <- make_toy_project()
  res <- run_shim(proj)
  expect_identical(res$status, 0L, info = res$stdout)
  expect_identical(res$stderr, "")
  lines <- strsplit(res$stdout, "\n")[[1]]
  expect_true(all(
    c(
      "== targets ==",
      "clean: completed",
      "prep: completed",
      "== errors and warnings (detail in the debug directory) ==",
      "  warned: warnings: <5",
      "== run status ==",
      "-- TOY --",
      "prep: completed",
      "decisions: 4"
    ) %in%
      lines
  ), info = res$stdout)
  expect_match(res$stdout, "debug directory: data/processed/debug/[0-9]{8}-[0-9]{6}\n$")
  expect_false(grepl(leaky, res$stdout))
  dbg <- debug_runs(proj)
  expect_length(dbg, 1L)
  # Positive controls: what stdout held back did reach the debug directory.
  expect_identical(readLines(file.path(dbg, "warnings_warned.txt")), "warning EARLY-9")
  expect_match(
    paste(readLines(file.path(dbg, "tar_make.log")), collapse = "\n"),
    "printed EARLY-8"
  )
})

test_that("a target error exits 1 with its code and masked counts, detail kept private", {
  skip_end_to_end()
  proj <- make_toy_project()
  res <- run_shim(proj, fail = TRUE)
  expect_identical(res$status, 1L, info = res$stdout)
  expect_identical(res$stderr, "")
  lines <- strsplit(res$stdout, "\n")[[1]]
  expect_true("prep: errored" %in% lines, info = res$stdout)
  expect_true(
    any(grepl(
      "^  prep: class=dctools_safe_error code=D5_norm n_bad=<5 n_rows=120 warnings: 0$",
      lines
    )),
    info = res$stdout
  )
  expect_false(grepl(leaky, res$stdout))
  dbg <- debug_runs(proj)
  expect_match(
    paste(readLines(file.path(dbg, "prep.txt")), collapse = "\n"),
    "row EARLY-1 has value 99"
  )
})

test_that("--names builds only the named targets, and a rerun skips them", {
  skip_end_to_end()
  proj <- make_toy_project()
  res <- run_shim(proj, c("--names", "run_status"))
  expect_identical(res$status, 0L, info = res$stdout)
  lines <- strsplit(res$stdout, "\n")[[1]]
  expect_true("run_status: completed" %in% lines, info = res$stdout)
  expect_false("clean: completed" %in% lines)
  expect_true("-- TOY --" %in% lines)
  res2 <- run_shim(proj, c("--names", "run_status"))
  expect_identical(res2$status, 0L)
  expect_true("run_status: skipped" %in% strsplit(res2$stdout, "\n")[[1]])
  expect_identical(res2$stderr, "")
})

test_that("bad arguments through the shim exit 2 and print only the class", {
  skip_end_to_end()
  proj <- make_toy_project()
  res <- run_shim(proj, c("--names", "x;y"))
  expect_identical(res$status, 2L)
  expect_identical(res$stdout, "runner failed: dctools_runner_usage_error\n")
  expect_identical(res$stderr, "")
})
