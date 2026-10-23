# Run Ledger and Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every number a `targets` pipeline reports can be traced mechanically to the committed code, inputs and store that produced it, checked by a fixed, tested audit (C1-C9) whose output a person can read in one page.

**Architecture:** A ported disclosure-safe report object records, for every count, the source lines and function that computed it. After `tar_make()`, `write_run_ledger()` writes a PHI-free JSON index of the run (git SHA, hashes, target metadata, provenance locations; no values), and `audit_run()` checks it against git, the store and the files on disk, writing `<run_id>.md` (verdict) and `<run_id>.provenance.md` (each value with its code). `run_targets_safe()` gains a `ledger` argument that refuses a dirty tree, then writes and audits the ledger after every run.

**Tech Stack:** R (>= 4.2), `targets`, `jsonlite`, `digest` (SHA-256), `processx`/`callr` (tests), git CLI, testthat 3e.

**Spec:** `memos/specs/2026-10-20-run-ledger-design.md` (merged in PR #18). Read it before starting.

## Deviations from the spec (approved with this plan)

1. **`add_count()` is named `record_count()`** (and `add_unprinted_count()` is `record_unprinted_count()`): `dplyr::add_count()` exists, and sepsis_burn attaches dplyr in its pipeline, so whichever package attached last would win. Task 11 updates the spec's table.
2. **The runner integration is in dctools.** Main now has `run_targets_safe()` (PR #16), so the ledger and audit hook into it (Task 10) instead of into sepsis_burn's own runner.
3. **`create_report()` has no `threshold` argument.** The suppression code uses the threshold of 5 throughout its proofs; parameterising it is not needed by any consumer.
4. **A failed `run_section()` prints only the error's class**, never its message (sepsis_burn printed up to 500 characters when no error sink was set). Report output is now committed to git, so error text, which can hold row-level values, must never reach it.
5. **`jsonlite` and `digest` are in Suggests**, guarded with `.require_pkgs()`, like the rest of `R/pipeline.R` (the spec said Imports). `quarto` is not needed: tests stamp a plain file.
6. **Unprovenanced numbers are recorded by location only**, never by value: the number itself may be a patient-level value or identifier.
7. **The audit is run-time only** (as the spec says), so the ledger's `targets` block also records each stored object file's SHA-256, which C2 and C7 compare.

## Global Constraints

- ASCII-only R sources (`R/` and `tests/`): no em-dashes, box-drawing characters or middle dots; use `\uxxxx` escapes if a non-ASCII character is unavoidable.
- Call imported and suggested functions fully qualified (`pkg::fn`); `NAMESPACE` stays export-only.
- Packages in Suggests (`targets`, `jsonlite`, `digest`, `processx`, `callr`, `pkgload`) are checked with the existing `.require_pkgs(pkgs, fn)` from `R/pipeline.R` before use; tests use `skip_if_not_installed()`.
- Names: functions `verb_noun()`, objects nouns; internals are `.dot_prefixed` and not exported.
- Every exported function has a roxygen block with `@param`, `@return`, `@examples` (wrapped in `\dontrun{}` when it needs a pipeline), `@export`, and at least one test.
- No PHI anywhere: fixtures use synthetic values; nothing writes a count's value or an error message into the ledger.
- Run from the worktree root `/Shared/Projects/dctools/.worktrees/feat-run-ledger`. Commands:
  - document: `Rscript -e 'roxygen2::roxygenise()'`
  - one test file: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/<file>")'`
  - all tests: `Rscript -e 'testthat::test_local(".")'`
  - format: `air format .` (`air` is at `~/.positron/extensions/posit.air-vscode-*/bundled/bin/air` if not on `PATH`)
  - check: `Rscript -e 'rcmdcheck::rcmdcheck(args = c("--no-manual", "--as-cran"), error_on = "warning")'`
- Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR
  ```

## Review Focus

1. **A value computed in code with no source file** (a function created by `eval(parse(text = ...))`, a Quarto chunk): provenance fields are `NA`, nothing crashes, and C8 fails naming the report and id. Test in Task 3 and Task 8.
2. **A reportable target that errored** (stored `NULL` by `error = "null"`) or was not built: the ledger and audit skip it rather than hard-stopping, C4 fails, and C8 evaluates the reports that exist. Test in Task 6 and Task 8.
3. **A git remote with embedded credentials** (`https://user:token@host/...`): the ledger and the audit page show it without the credentials. Test in Task 6.
4. **Input paths with spaces** (sepsis_burn reads `Bridging samples informations.xls`): hashing, git and the "verify by hand" commands all handle them. Test in Task 6 (fixture input `data/raw/input values.csv`) and Task 9 (quoted in the md).
5. **Code sourced through a relative path** (`source("R/x.R")` from the project root): provenance resolves to an absolute path at run time and to a repo-relative path in the ledger. Test in Task 1 and Task 6.

## File structure

| File | Responsibility |
|---|---|
| `R/provenance.R` (new) | Capturing where a call came from: source lines, enclosing function, target; the bare-number guard |
| `R/report.R` (new) | The report object and its exported API (`create_report()`, `record_count()`, `add_*()`, `run_section()`, printing) |
| `R/report-suppression.R` (new) | Ported small-count suppression internals and the placeholder resolver (internal only) |
| `R/git.R` (new) | Internal git and SHA-256 helpers |
| `R/stamp.R` (new) | `stamp_record()` and parsing stamps back |
| `R/ledger.R` (new) | `write_run_ledger()` and its blocks |
| `R/audit.R` (new) | `audit_run()`, checks C1-C9, verdict, hard stops |
| `R/audit-render.R` (new) | `<run_id>.md` and `<run_id>.provenance.md` |
| `R/pipeline.R` (modify) | `run_targets_safe(ledger = )`: preflight, ledger, audit, exit 3 |
| `tests/testthat/helper-subprocess.R` (new) | `dctools_src()`, `load_dctools_line`, `run_rscript()`, `skip_subprocess()` (moved out of `test-pipeline-runner.R`) |
| `tests/testthat/helper-report.R` (new) | `source_user_code()`: write lines to a temp `.R` file and source it with source references |
| `tests/testthat/helper-ledger-fixture.R` (new) | The fixture pipeline project, built once and copied per test |
| `tests/testthat/test-provenance.R`, `test-report.R`, `test-report-provenance.R`, `test-bare-numbers.R`, `test-stamp.R`, `test-ledger.R`, `test-audit-core.R`, `test-audit-checks.R`, `test-audit-render.R`, `test-pipeline-ledger.R` (new) | Tests per task |

---

### Task 1: Provenance capture (feasibility gate)

**Files:**
- Create: `R/provenance.R`
- Create: `tests/testthat/helper-subprocess.R`
- Modify: `tests/testthat/test-pipeline-runner.R` (delete the `dctools_src` and `load_dctools_line` definitions, now in the helper)
- Test: `tests/testthat/test-provenance.R`

**Interfaces:**
- Produces: `.capture_provenance(call, env)` returning a list with exactly these fields: `file` (absolute path or `NA_character_`), `line_start`, `line_end` (integer or `NA_integer_`), `code` (the full source lines, joined by `"\n"`, or `NA_character_`), `function_name`, `function_file`, `function_line_start`, `function_line_end`, `target` (`targets::tar_name()` or `NA_character_`). Also `.srcref_path(srcref)`, `.srcref_lines(srcref)`, `.is_missing(x)`.
- Produces (tests): `dctools_src()`, `load_dctools_line`, `run_rscript(wd, script, args = character(0), env = character(0))` returning the `processx::run()` result with `\r\n` normalised, `skip_subprocess(pkgs)`.

**Gate:** this task proves the spec's central assumption. If the in-process, Rscript and targets tests cannot all pass (after also trying `sys.calls()[[sys.nframe()]]` in place of `sys.call()` inside the probe), STOP, do not start Task 2, and report the failing output to the human: the spec returns to review.

- [ ] **Step 1: Move the subprocess helpers**

Create `tests/testthat/helper-subprocess.R`:

```r
# Shared by tests that run R in a subprocess (Rscript shims, targets runs).

# The package source when testing from a checkout (load_all); "" when the
# tests run against an installed dctools (R CMD check, covr). An installed
# package also has a DESCRIPTION, so look for the R sources themselves.
dctools_src <- function() {
  src <- getNamespaceInfo(asNamespace("dctools"), "path")
  if (file.exists(file.path(src, "R", "pipeline.R"))) src else ""
}

load_dctools_line <- paste0(
  "if (nzchar(Sys.getenv('DCTOOLS_TEST_SRC'))) ",
  "pkgload::load_all(Sys.getenv('DCTOOLS_TEST_SRC'), quiet = TRUE) ",
  "else library(dctools)"
)

skip_subprocess <- function(pkgs = "processx") {
  skip_on_cran()
  for (p in pkgs) {
    skip_if_not_installed(p)
  }
  if (nzchar(dctools_src())) skip_if_not_installed("pkgload")
}

# Rscript `script` (relative to `wd`) with dctools loadable in the child.
run_rscript <- function(wd, script, args = character(0), env = character(0)) {
  res <- processx::run(
    file.path(R.home("bin"), "Rscript"),
    c(script, args),
    wd = wd,
    error_on_status = FALSE,
    env = c(
      "current",
      DCTOOLS_TEST_SRC = dctools_src(),
      R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
      env
    )
  )
  res$stdout <- gsub("\r\n", "\n", res$stdout, fixed = TRUE)
  res$stderr <- gsub("\r\n", "\n", res$stderr, fixed = TRUE)
  res
}
```

In `tests/testthat/test-pipeline-runner.R`, delete these two definitions (the comment block above `dctools_src` included), leaving `skip_end_to_end()`, `make_toy_project()` and `run_shim()` unchanged:

```r
# The package source when testing from a checkout (load_all); "" when the
# tests run against an installed dctools (R CMD check, covr). An installed
# package also has a DESCRIPTION, so look for the R sources themselves.
dctools_src <- function() {
  src <- getNamespaceInfo(asNamespace("dctools"), "path")
  if (file.exists(file.path(src, "R", "pipeline.R"))) src else ""
}

load_dctools_line <- paste0(
  "if (nzchar(Sys.getenv('DCTOOLS_TEST_SRC'))) ",
  "pkgload::load_all(Sys.getenv('DCTOOLS_TEST_SRC'), quiet = TRUE) ",
  "else library(dctools)"
)
```

Run: `Rscript -e 'testthat::test_local(".", filter = "pipeline-runner")'`
Expected: same pass count as before the move, 0 failures.

- [ ] **Step 2: Write the failing tests**

Create `tests/testthat/test-provenance.R`:

```r
# Probe files: lib.R stands in for a dctools function that records provenance;
# user.R is project code calling it.
write_probe_files <- function(dir) {
  writeLines(
    c(
      "grab <- function(expr) {",
      "  call <- sys.call()",
      "  env <- parent.frame()",
      "  force(expr)",
      "  dctools:::.capture_provenance(call, env)",
      "}"
    ),
    file.path(dir, "lib.R")
  )
  writeLines(
    c(
      "user_fn <- function() {",
      "  y <- 1",
      "  grab(",
      "    y + 1",
      "  )",
      "}",
      "user_nested <- function(wrap) {",
      "  wrap({",
      "    grab(3)",
      "  })",
      "}"
    ),
    file.path(dir, "user.R")
  )
}

source_probe <- function(dir, keep_source = TRUE) {
  env <- new.env()
  source(file.path(dir, "lib.R"), local = env, keep.source = keep_source)
  source(file.path(dir, "user.R"), local = env, keep.source = keep_source)
  env
}

test_that(".capture_provenance names the calling statement and its function", {
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  p <- source_probe(dir)$user_fn()
  expect_identical(basename(p$file), "user.R")
  expect_true(grepl("^(/|[A-Za-z]:)", p$file))
  expect_identical(c(p$line_start, p$line_end), c(3L, 5L))
  expect_identical(p$code, "  grab(\n    y + 1\n  )")
  expect_identical(p$function_name, "user_fn")
  expect_identical(basename(p$function_file), "user.R")
  expect_identical(c(p$function_line_start, p$function_line_end), c(1L, 6L))
  expect_identical(p$target, NA_character_)
})

test_that("a call inside a code block passed to another function keeps its own line and function", {
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  p <- source_probe(dir)$user_nested(function(code) force(code))
  expect_identical(c(p$line_start, p$line_end), c(9L, 9L))
  expect_identical(p$code, "    grab(3)")
  expect_identical(p$function_name, "user_nested")
  expect_identical(c(p$function_line_start, p$function_line_end), c(7L, 11L))
})

test_that("without keep.source the source fields are NA, not guessed", {
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  p <- source_probe(dir, keep_source = FALSE)$user_fn()
  expect_identical(p$file, NA_character_)
  expect_identical(p$line_start, NA_integer_)
  expect_identical(p$code, NA_character_)
  expect_identical(p$function_file, NA_character_)
  expect_identical(p$function_name, "user_fn")
})

test_that("code with no source file (eval of parsed text) gives NA source fields", {
  env <- new.env()
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  source(file.path(dir, "lib.R"), local = env, keep.source = TRUE)
  eval(parse(text = "f <- function() grab(1)", keep.source = TRUE), env)
  p <- env$f()
  expect_identical(p$file, NA_character_)
  expect_identical(p$function_name, "f")
})

test_that("source references survive Rscript when sourced with keep.source = TRUE", {
  skip_subprocess()
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  writeLines(
    c(
      load_dctools_line,
      "source('lib.R', keep.source = TRUE)",
      "source('user.R', keep.source = TRUE)",
      "p <- user_fn()",
      "cat(basename(p$file), grepl('^(/|[A-Za-z]:)', p$file), p$line_start,",
      "  p$line_end, p$function_name, sep = '|')"
    ),
    file.path(dir, "probe.R")
  )
  res <- run_rscript(dir, "probe.R")
  expect_identical(res$stdout, "user.R|TRUE|3|5|user_fn", info = res$stderr)
})

test_that("source references and the target name survive a targets run", {
  skip_subprocess(c("processx", "targets", "callr"))
  dir <- withr::local_tempdir()
  write_probe_files(dir)
  writeLines(
    c(
      "library(targets)",
      load_dctools_line,
      "source('lib.R', keep.source = TRUE)",
      "source('user.R', keep.source = TRUE)",
      "list(tar_target(probe, user_fn()))"
    ),
    file.path(dir, "_targets.R")
  )
  writeLines(
    c(
      "targets::tar_make(reporter = 'silent')",
      "p <- targets::tar_read(probe)",
      "cat(basename(p$file), p$line_start, p$line_end, p$function_name,",
      "  p$target, sep = '|')"
    ),
    file.path(dir, "run.R")
  )
  res <- run_rscript(dir, "run.R")
  expect_identical(res$stdout, "user.R|3|5|user_fn|probe", info = res$stderr)
})
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-provenance.R")'`
Expected: FAIL, `.capture_provenance` not found.

- [ ] **Step 4: Implement**

Create `R/provenance.R`:

```r
# Provenance of report values -------------------------------------------------
#
# Where a value in a report came from: the source lines of the statement that
# computed it, the function that statement sits in, and the targets target
# that ran it. Source references exist only for code sourced with
# `keep.source = TRUE`; anything not found is NA, and the audit (C8) fails it.

.is_missing <- function(x) {
  is.null(x) || (length(x) == 1L && is.na(x))
}

# The innermost frame whose environment is `env`, or NA.
.frame_of <- function(env) {
  hit <- which(vapply(sys.frames(), identical, logical(1), env))
  if (length(hit)) max(hit) else NA_integer_
}

# Absolute path of a srcref's file; NA for parsed text ("<text>") or no file.
.srcref_path <- function(srcref) {
  srcfile <- attr(srcref, "srcfile")
  name <- if (is.environment(srcfile)) srcfile$filename else NULL
  if (is.null(name) || !nzchar(name) || startsWith(name, "<")) {
    return(NA_character_)
  }
  if (!grepl("^(/|[A-Za-z]:[/\\\\])", name) && !is.null(srcfile$wd)) {
    name <- file.path(srcfile$wd, name)
  }
  normalizePath(name, winslash = "/", mustWork = FALSE)
}

# The whole source lines a srcref spans, joined with "\n"; NA if unavailable.
.srcref_lines <- function(srcref) {
  srcfile <- attr(srcref, "srcfile")
  lines <- tryCatch(
    utils::getSrcLines(srcfile, srcref[[1]], srcref[[3]]),
    error = function(e) character(0)
  )
  if (length(lines)) paste(lines, collapse = "\n") else NA_character_
}

# The called function's name: f(), pkg::f(), env$f() all give "f".
.call_name <- function(call) {
  fn <- if (is.call(call)) call[[1]] else NULL
  if (is.symbol(fn)) {
    return(as.character(fn))
  }
  if (
    is.call(fn) &&
      length(fn) == 3L &&
      as.character(fn[[1]]) %in% c("::", ":::", "$", "@") &&
      (is.symbol(fn[[3]]) || is.character(fn[[3]]))
  ) {
    return(as.character(fn[[3]]))
  }
  NA_character_
}

.current_target <- function() {
  if (!requireNamespace("targets", quietly = TRUE)) {
    return(NA_character_)
  }
  targets::tar_name(default = NA_character_)
}

# Provenance of `call` (a call as returned by sys.call(), which carries the
# "srcref" of the statement it was made from) made from the frame whose
# environment is `env` (the caller's parent.frame()).
.capture_provenance <- function(call, env) {
  out <- list(
    file = NA_character_,
    line_start = NA_integer_,
    line_end = NA_integer_,
    code = NA_character_,
    function_name = NA_character_,
    function_file = NA_character_,
    function_line_start = NA_integer_,
    function_line_end = NA_integer_,
    target = .current_target()
  )
  srcref <- attr(call, "srcref")
  if (!is.null(srcref)) {
    out$file <- .srcref_path(srcref)
    out$line_start <- as.integer(srcref[[1]])
    out$line_end <- as.integer(srcref[[3]])
    out$code <- .srcref_lines(srcref)
  }
  n <- .frame_of(env)
  if (!is.na(n) && n > 0L) {
    out$function_name <- .call_name(sys.call(n))
    fn_srcref <- attr(sys.function(n), "srcref")
    if (!is.null(fn_srcref)) {
      out$function_file <- .srcref_path(fn_srcref)
      out$function_line_start <- as.integer(fn_srcref[[1]])
      out$function_line_end <- as.integer(fn_srcref[[3]])
    }
  }
  out
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-provenance.R")'`
Expected: 6 tests pass, 0 fail. If the Rscript or targets tests fail on the source fields, apply the Gate above.

- [ ] **Step 6: Commit**

```bash
git add R/provenance.R tests/testthat/helper-subprocess.R tests/testthat/test-pipeline-runner.R tests/testthat/test-provenance.R
git commit -m "feat(provenance): capture the source lines and function of a call

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR"
```

---

### Task 2: Port the disclosure-safe report

**Files:**
- Create: `R/report-suppression.R` (mechanical port of sepsis_burn lines 167-621 and 624-673)
- Create: `R/report.R`
- Test: `tests/testthat/test-report.R` (ported from sepsis_burn's `tests/testthat/test-disclosure-safe-report.R`)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces (exported): `create_report(hide_small_counts = TRUE, error_sink = NULL)` returning an environment of class `"dctools_report"` with fields `hide_small_counts`, `error_sink`, `dctools_version`, `counts`, `protected_ids`, `relations`, `unprinted_counts`, `output_steps`, `current_section_id`, `section_ids`, `provenance` (named list, filled in Task 3), `unprovenanced` (list, filled in Task 4), `resolver`, `decision`, `n_failed_sections`, `n_warnings`, `n_messages`, `is_rendered`; `record_count(report, id, expr, protect = FALSE)` returning the placeholder `"{{id}}"`; `record_unprinted_count(report, id, expr)`; `declare_linear_relation(report, coefficients, total_id = NULL)`; `declare_sum_relation(report, part_ids, total_id = NULL)`; `add_line(report, ...)`; `add_literal_line(report, text)`; `add_data_frame(report, data)`; `add_count_table(report, id, expr, protect = FALSE, labels_from_code = FALSE, total_id = NULL, max_levels = 30L)`; `add_tabulation(report, id, expr, ...)`; `run_section(report, title, code, section_id = title, heading = TRUE)`; `render_report(report)`; `print_report_section(report, section_id, include_heading = FALSE)`.
- Produces (internal, used by Tasks 3, 4, 9): `.register_count(report, id, value, protect)` returning the final id; `.add_count_table_impl(report, id, counts, protect, labels_from_code, total_id, max_levels, provenance = NULL)`; `.add_output_step(report, print_step, is_heading = FALSE)`; `.prepare_report_for_printing(report)`; `.placeholder_pattern`; `.disclosure_threshold`; `.decide_which_counts_to_hide(report)`; `.count_upper_bound(report)`; `.sanitize_labels(labels)`.

- [ ] **Step 1: Port the tests**

```bash
SB=/Shared/Projects/UCSF/Legrand_Matthieu/sepsis_burn
git -C "$SB" show 0cd21c0:tests/testthat/test-disclosure-safe-report.R > tests/testthat/test-report.R
sed -i \
  -e '/^source(here::here/d' \
  -e 's/^#### \(.*\) [^ -~]*$/# ---- \1 ----/' \
  -e 's/\bnew_disclosure_safe_report\b/create_report/g' \
  -e 's/\bregister_unprinted_count\b/record_unprinted_count/g' \
  -e 's/\bregister_count\b/record_count/g' \
  -e 's/\bdecide_which_counts_to_hide\b/.decide_which_counts_to_hide/g' \
  -e 's/\bcount_upper_bound\b/.count_upper_bound/g' \
  -e 's/\bsanitize_labels\b/.sanitize_labels/g' \
  -e 's/^# Synthetic-vector tests of the small-cell suppression helpers used by$/# Synthetic-vector tests of the report'"'"'s small-cell suppression (ported from/' \
  -e 's/^# check_earlyburn_prep.R and compare_earlyburn_clinical_sources.qmd. No data files are read.$/# sepsis_burn tests\/testthat\/test-disclosure-safe-report.R). No data files are read./' \
  tests/testthat/test-report.R
LC_ALL=C grep -nP '[^\x00-\x7F]' tests/testthat/test-report.R || echo ASCII-OK
```

Expected: `ASCII-OK`.

Then make these three edits in `tests/testthat/test-report.R` (behaviour changes 4 and the error-sink constructor argument, plus `within_report_section()` folded into `run_section()`):

Replace the test `"section: errors are recorded capped at 500 chars, warnings only counted"` with:

```r
test_that("section: a failure prints only its class, warnings are only counted", {
  report <- create_report()
  run_section(report, "boom", stop(strrep("z", 900)))
  run_section(report, "warn", warning("secret-looking text"))
  expect_equal(report$n_failed_sections, 1L)
  expect_equal(report$n_warnings, 1L)
  txt <- paste(capture.output(render_report(report)), collapse = "\n")
  expect_false(grepl("zzz", txt))
  expect_match(txt, "SECTION FAILED: simpleError", fixed = TRUE)
  expect_false(grepl("secret-looking", txt))
})
```

Replace `within_report_section(report, "closing", add_line(report, "total: {{total}}"))` with:

```r
run_section(report, "closing", add_line(report, "total: {{total}}"), heading = FALSE)
```

Replace the last test (`"run_section: with an error_sink, ..."`) with:

```r
test_that("run_section: with an error_sink, the report shows the class, not the message", {
  seen <- NULL
  report <- create_report(
    hide_small_counts = FALSE,
    error_sink = function(condition) seen <<- conditionMessage(condition)
  )
  run_section(report, "s", stop("secret value 42"), section_id = "s")
  printed <- paste(capture.output(print_report_section(report, "s")), collapse = "\n")
  expect_false(grepl("secret value 42", printed))
  expect_match(printed, "SECTION FAILED: simpleError")
  expect_identical(seen, "secret value 42")
})

test_that("create_report returns a classed report that records the engine version", {
  r <- create_report()
  expect_s3_class(r, "dctools_report")
  expect_identical(r$dctools_version, as.character(utils::packageVersion("dctools")))
  expect_identical(r$section_ids, character(0))
  expect_error(create_report(error_sink = "x"), "error_sink")
})

test_that("run_section records its section id, with or without a heading", {
  r <- create_report()
  run_section(r, "A title", add_line(r, "x"))
  run_section(r, "quiet", add_line(r, "y"), heading = FALSE)
  expect_identical(r$section_ids, c("A title", "quiet"))
  out <- capture.output(print_report_section(r, "quiet", include_heading = TRUE))
  expect_identical(out, "y")
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-report.R")'`
Expected: FAIL, `create_report` not found.

- [ ] **Step 3: Port the suppression internals**

```bash
SB=/Shared/Projects/UCSF/Legrand_Matthieu/sepsis_burn
SRC=$(mktemp)
git -C "$SB" show 0cd21c0:code/functions/disclosure_safe_report.R > "$SRC"
sed -n '166p;621p;673p' "$SRC"   # expect: an empty line, "}", "}"
{
  echo "# Small-count suppression for reports (internal) ------------------------"
  echo "#"
  echo "# Ported unchanged in behaviour from sepsis_burn"
  echo "# code/functions/disclosure_safe_report.R (commit 0cd21c0), lines 167-673:"
  echo "# deciding which counts to hide, and resolving {{id}} placeholders. The"
  echo "# rules are documented in R/report.R."
  echo
  echo "# ---- Deciding what to hide ----"
  echo
  sed -n '167,621p' "$SRC"
  echo
  echo "# ---- Turning counts into text ----"
  echo
  sed -n '624,673p' "$SRC"
} > R/report-suppression.R
sed -i \
  -e "s/^\( *\)#' \?/\1# /" \
  -e 's/\bDISCLOSURE_THRESHOLD\b/.disclosure_threshold/g' \
  -e 's/\bPLACEHOLDER_PATTERN\b/.placeholder_pattern/g' \
  -e 's/\bcount_upper_bound\b/.count_upper_bound/g' \
  -e 's/\bindex_relation_coefficients\b/.index_relation_coefficients/g' \
  -e 's/\bmake_shift_finder\b/.make_shift_finder/g' \
  -e 's/\bmake_small_count_checker\b/.make_small_count_checker/g' \
  -e 's/\bindex_relations\b/.index_relations/g' \
  -e 's/\brank_counts_to_hide\b/.rank_counts_to_hide/g' \
  -e 's/\bdecide_which_counts_to_hide\b/.decide_which_counts_to_hide/g' \
  -e 's/\bformat_count\b/.format_count/g' \
  -e 's/\bmake_placeholder_resolver\b/.make_placeholder_resolver/g' \
  R/report-suppression.R
LC_ALL=C grep -nP '[^\x00-\x7F]' R/report-suppression.R || echo ASCII-OK
grep -n "^[a-z]" R/report-suppression.R || echo NO-PUBLIC-NAMES
grep -nE "\b(register_count|add_output_step|stop_if_prepared_for_printing|sanitize_labels|prepare_report_for_printing)\b" R/report-suppression.R || echo NO-STALE-REFS
```

Expected: `ASCII-OK`, `NO-PUBLIC-NAMES` and `NO-STALE-REFS` (if the last prints lines, rename each reference to the dot-prefixed internal of the same name in `R/report.R`). If the ASCII check prints lines, replace each non-ASCII character in them with ASCII (`-` for dashes, `x` for multiplication signs) by hand.

- [ ] **Step 4: Write `R/report.R`**

```r
# Disclosure-safe reports ------------------------------------------------------
#
# A report collects counts and text and prints them so that small counts
# cannot be read or recovered (ported from sepsis_burn's
# disclosure_safe_report.R). Every number enters through record_count() /
# record_unprinted_count() / add_count_table() / add_tabulation(), which also
# record where in the source it was computed (R/provenance.R), so an audit
# can point at the code behind every printed value.
#
# The rules, applied when the report is printed:
#   1. Small counts: a count of 1 to 4 is printed as "<5". Zero is printed as 0.
#   2. Totals: the total of a group that contains a small count is hidden
#      ("<suppr.>") unless it was registered with `protect = TRUE`.
#   3. Secondary suppression: a reader is assumed to know that a "<5" cell is
#      1-4, that a "<suppr.>" cell is 5 or more, that printed values are exact,
#      and that every declared relation holds. Each "<5" cell must remain
#      consistent with EVERY value 1-4 under those assumptions; otherwise one
#      more count is hidden, largest first, non-protected before protected,
#      nearest relation first.
#   4. Percentages are printed only when all of their inputs are printed.
# Only declared linear relations are modelled; inequalities are not.

.disclosure_threshold <- 5L # counts from 1 to threshold - 1 are never printed
.placeholder_pattern <- "\\{\\{([^{}]+)\\}\\}"

#' Create an empty disclosure-safe report
#'
#' A report is an environment that accumulates counts, relations between
#' them and output, and prints them with small counts hidden (see
#' [render_report()]). Counts enter only through [record_count()],
#' [record_unprinted_count()], [add_count_table()] and [add_tabulation()],
#' which also record the source lines that computed each one.
#'
#' @param hide_small_counts Hide counts of 1-4 and anything that would reveal
#'   them (`TRUE`, the default), or print every count exactly (`FALSE`, for
#'   output that stays with people allowed to see the data).
#' @param error_sink `NULL` or a function of one condition, called with the
#'   error when a [run_section()] block fails (e.g. [create_debug_sink()]).
#'   The report itself prints only the error's class.
#' @return An environment of class `"dctools_report"`.
#' @seealso [record_count()], [render_report()].
#' @examples
#' r <- create_report()
#' add_line(r, "patients: ", record_count(r, "n", 12))
#' render_report(r)
#' @export
create_report <- function(hide_small_counts = TRUE, error_sink = NULL) {
  if (!is.null(error_sink) && !is.function(error_sink)) {
    cli::cli_abort("{.arg error_sink} must be NULL or a function.")
  }
  report <- new.env(parent = emptyenv())
  report$hide_small_counts <- isTRUE(hide_small_counts)
  report$error_sink <- error_sink
  report$dctools_version <- as.character(utils::packageVersion("dctools"))
  report$counts <- numeric(0)
  report$protected_ids <- character(0)
  report$relations <- list()
  report$unprinted_counts <- numeric(0)
  report$output_steps <- list()
  report$current_section_id <- NA_character_
  report$section_ids <- character(0)
  report$provenance <- list()
  report$unprovenanced <- list()
  report$resolver <- NULL
  report$decision <- NULL
  report$n_failed_sections <- 0L
  report$n_warnings <- 0L
  report$n_messages <- 0L
  report$is_rendered <- FALSE
  class(report) <- "dctools_report"
  report
}

# Once what to hide has been decided, a new count or relation would make the
# decision stale, so it is an error rather than a silently wrong report.
.stop_if_prepared <- function(report) {
  if (!is.null(report$resolver)) {
    stop(
      "the report has already been prepared for printing; ",
      "register counts and relations before printing any section",
      call. = FALSE
    )
  }
}

# Registering an existing id with a different value creates a new id
# ("id_2", ...) instead of overwriting. Returns the id used.
.register_count <- function(report, id, value, protect = FALSE) {
  .stop_if_prepared(report)
  value <- as.numeric(value)
  base_id <- id
  suffix <- 1L
  while (
    id %in% names(report$counts) &&
      !isTRUE(all.equal(report$counts[[id]], value))
  ) {
    suffix <- suffix + 1L
    id <- paste0(base_id, "_", suffix)
  }
  report$counts[id] <- value
  if (protect) {
    report$protected_ids <- union(report$protected_ids, id)
  }
  id
}

#' Record a count in a report
#'
#' Evaluates `expr`, registers the value under `id`, and returns a
#' placeholder (`"{{id}}"`) to put in text passed to [add_line()] or
#' [add_data_frame()]; printing replaces it with the number, `"<5"` or
#' `"<suppr.>"`. The source lines of this call and the function it sits in
#' are recorded with the count (they exist only for code sourced with
#' `keep.source = TRUE`).
#'
#' @param report A report from [create_report()].
#' @param id The count's id. If `id` is already registered with a different
#'   value, `"id_2"`, `"id_3"`, ... is used instead.
#' @param expr The expression computing the count.
#' @param protect Keep this count visible if at all possible (results the
#'   reader must see, such as cohort sizes).
#' @return The placeholder string, e.g. `"{{n}}"`.
#' @seealso [create_report()], [declare_sum_relation()].
#' @examples
#' r <- create_report()
#' add_line(r, "rows: ", record_count(r, "n_rows", nrow(mtcars)))
#' render_report(r)
#' @export
record_count <- function(report, id, expr, protect = FALSE) {
  id <- .register_count(report, id, expr, protect)
  paste0("{{", id, "}}")
}

#' Record a quantity used in relations but never printed
#'
#' @param report A report from [create_report()].
#' @param id The quantity's id; must start with `"~"`.
#' @param expr The expression computing it.
#' @return `id`, invisibly.
#' @seealso [declare_linear_relation()].
#' @examples
#' r <- create_report()
#' record_unprinted_count(r, "~excluded", 3)
#' @export
record_unprinted_count <- function(report, id, expr) {
  .stop_if_prepared(report)
  stopifnot(startsWith(id, "~"))
  report$unprinted_counts[id] <- as.numeric(expr)
  invisible(id)
}

#' Declare a linear relation between counts
#'
#' Declares `sum(coefficients * counts) = 0`, so that suppression accounts
#' for what a reader could recover from it.
#'
#' @param report A report from [create_report()].
#' @param coefficients A named numeric vector; names are count ids (ids of
#'   unprinted quantities start with `"~"`).
#' @param total_id `NULL` or the id of the total in a "parts add up to a
#'   total" relation; it is what gets hidden when a part is small.
#' @return `TRUE` invisibly, or `FALSE` (relation skipped) if it mentions a
#'   printed count that was never registered.
#' @seealso [declare_sum_relation()].
#' @examples
#' r <- create_report()
#' record_count(r, "a", 3)
#' record_count(r, "b", 9)
#' record_count(r, "total", 12)
#' declare_linear_relation(r, c(a = 1, b = 1, total = -1), total_id = "total")
#' @export
declare_linear_relation <- function(report, coefficients, total_id = NULL) {
  .stop_if_prepared(report)
  ids <- names(coefficients)
  is_known <- ids %in% names(report$counts) | startsWith(ids, "~")
  if (!all(is_known)) {
    return(invisible(FALSE))
  }
  new_relation <- list(coefficients = coefficients, total_id = total_id)
  report$relations[[length(report$relations) + 1L]] <- new_relation
  invisible(TRUE)
}

#' Declare that counts add up to a total
#'
#' @inheritParams declare_linear_relation
#' @param part_ids Ids of the parts.
#' @param total_id `NULL` or the id of the total.
#' @return As [declare_linear_relation()].
#' @examples
#' r <- create_report()
#' record_count(r, "a", 3)
#' record_count(r, "b", 9)
#' record_count(r, "total", 12)
#' declare_sum_relation(r, c("a", "b"), "total")
#' @export
declare_sum_relation <- function(report, part_ids, total_id = NULL) {
  coefficients <- stats::setNames(rep(1, length(part_ids)), part_ids)
  if (!is.null(total_id)) {
    coefficients <- c(coefficients, stats::setNames(-1, total_id))
  }
  declare_linear_relation(report, coefficients, total_id = total_id)
}

# Output is queued, not printed, because what may be shown depends on ALL the
# counts registered by the time the report is printed.
.add_output_step <- function(report, print_step, is_heading = FALSE) {
  new_step <- list(
    section_id = report$current_section_id,
    is_heading = is_heading,
    print_step = print_step
  )
  report$output_steps[[length(report$output_steps) + 1L]] <- new_step
  invisible(NULL)
}

#' Add text to a report
#'
#' `add_line()` pastes its arguments into one line that may contain count
#' placeholders; `add_literal_line()` prints `text` exactly as given;
#' `add_data_frame()` prints a data frame whose cells may contain
#' placeholders.
#'
#' @param report A report from [create_report()].
#' @param ... Pieces of the line, pasted with no separator.
#' @return `NULL`, invisibly.
#' @examples
#' r <- create_report()
#' add_line(r, "n = ", record_count(r, "n", 30))
#' add_literal_line(r, "-- notes --")
#' add_data_frame(r, data.frame(group = "A", n = record_count(r, "n_a", 7)))
#' render_report(r)
#' @export
add_line <- function(report, ...) {
  text <- paste0(...)
  .add_output_step(report, function(resolve) cat(resolve(text), "\n", sep = ""))
}

#' @rdname add_line
#' @param text A line printed with no placeholder parsing.
#' @export
add_literal_line <- function(report, text) {
  force(text)
  .add_output_step(report, function(resolve) cat(text, "\n", sep = ""))
}

#' @rdname add_line
#' @param data A data frame; every cell is printed as text.
#' @export
add_data_frame <- function(report, data) {
  force(data)
  .add_output_step(report, function(resolve) {
    resolved <- data
    resolved[] <- lapply(resolved, function(column) {
      resolve(as.character(column))
    })
    print(resolved, row.names = FALSE)
  })
}

# Labels that come from data print only if they are short and identifier-like.
.sanitize_labels <- function(labels) {
  ifelse(
    is.na(labels),
    NA_character_,
    ifelse(grepl("^[A-Za-z0-9_ .-]{1,20}$", labels), labels, "<other>")
  )
}

.add_count_table_impl <- function(
  report,
  id,
  counts,
  protect,
  labels_from_code,
  total_id,
  max_levels,
  provenance = NULL
) {
  dimensions <- dim(counts)
  if (any(dimensions > max_levels)) {
    note <- paste0(
      "  (",
      paste(dimensions, collapse = " x "),
      " levels; not printed)"
    )
    .add_output_step(report, function(resolve) cat(note, "\n", sep = ""))
    return(invisible(NULL))
  }
  cell_ids <- array(paste0(id, ".", seq_along(counts)), dim = dimensions)
  cell_placeholders <- cell_ids
  for (i in seq_along(counts)) {
    cell_ids[i] <- .register_count(report, cell_ids[i], counts[i], protect)
    cell_placeholders[i] <- paste0("{{", cell_ids[i], "}}")
    if (!is.null(provenance)) {
      .store_provenance(report, cell_ids[i], provenance)
    }
  }
  if (!is.null(total_id)) {
    declare_sum_relation(report, as.vector(cell_ids), total_id)
  }
  labels <- dimnames(counts)
  if (!labels_from_code) {
    labels <- lapply(labels, .sanitize_labels)
  }
  names(labels) <- names(dimnames(counts))
  dimnames(cell_placeholders) <- labels
  .add_output_step(report, function(resolve) {
    printable <- cell_placeholders
    printable[] <- resolve(as.vector(cell_placeholders))
    print(printable, quote = FALSE)
  })
  invisible(list(ids = cell_ids, placeholders = cell_placeholders))
}

#' Add a table of counts to a report
#'
#' `add_count_table()` registers every cell of a one- or two-way table of
#' counts and adds the table; `add_tabulation()` tabulates a vector
#' (including `NA`) first. A dimension with more than `max_levels` levels is
#' not printed; only a note is added.
#'
#' @param report A report from [create_report()].
#' @param id Prefix of the cell ids (`"<id>.1"`, `"<id>.2"`, ...).
#' @param expr For `add_count_table()`, an expression giving a table (or
#'   array) of counts; for `add_tabulation()`, a vector to tabulate.
#' @param protect Keep the cells visible if at all possible.
#' @param labels_from_code `TRUE` when the dimension labels are constants in
#'   the code; otherwise labels that are not short and identifier-like print
#'   as `"<other>"`.
#' @param total_id `NULL` or the id of a registered count equal to the sum of
#'   all cells.
#' @param max_levels The largest number of levels a printed dimension may
#'   have.
#' @param ... For `add_tabulation()`, passed to `add_count_table()`.
#' @return A list with the cell `ids` and `placeholders` (arrays shaped like
#'   the table), invisibly; `NULL` when the table was too large to print.
#' @examples
#' r <- create_report()
#' add_tabulation(r, "cyl", mtcars$cyl, labels_from_code = TRUE)
#' render_report(r)
#' @export
add_count_table <- function(
  report,
  id,
  expr,
  protect = FALSE,
  labels_from_code = FALSE,
  total_id = NULL,
  max_levels = 30L
) {
  .add_count_table_impl(
    report,
    id,
    expr,
    protect,
    labels_from_code,
    total_id,
    max_levels
  )
}

#' @rdname add_count_table
#' @export
add_tabulation <- function(report, id, expr, ...) {
  tabulated <- table(expr, useNA = "ifany", dnn = NULL)
  add_count_table(report, id, tabulated, ...)
}

#' Run one block of report-building code
#'
#' The block's output is filed under `section_id` (for
#' [print_report_section()]), after a heading line `"-- <title> --"` when
#' `heading = TRUE`. An error ends the block: the report prints
#' `"SECTION FAILED: <class>"` (never the message, which may hold row-level
#' values) and the condition goes to the report's `error_sink`. Warnings and
#' messages are counted, never printed. Assignments inside `code` happen in
#' the caller's environment.
#'
#' @param report A report from [create_report()].
#' @param title The section's title.
#' @param code The block of code.
#' @param section_id The id the output is filed under (default: `title`).
#' @param heading Whether to add the heading line.
#' @return `NULL`, invisibly.
#' @examples
#' r <- create_report()
#' run_section(r, "Counts", add_line(r, "n = ", record_count(r, "n", 8)))
#' render_report(r)
#' @export
run_section <- function(
  report,
  title,
  code,
  section_id = title,
  heading = TRUE
) {
  force(title) # the heading prints later, after loop variables have moved on
  force(section_id)
  previous_section_id <- report$current_section_id
  report$current_section_id <- section_id
  on.exit(report$current_section_id <- previous_section_id, add = TRUE)
  report$section_ids <- union(report$section_ids, section_id)
  if (heading) {
    .add_output_step(
      report,
      function(resolve) cat("\n-- ", title, " --\n", sep = ""),
      is_heading = TRUE
    )
  }
  tryCatch(
    withCallingHandlers(
      force(code),
      warning = function(warning_condition) {
        report$n_warnings <- report$n_warnings + 1L
        invokeRestart("muffleWarning")
      },
      message = function(message_condition) {
        report$n_messages <- report$n_messages + 1L
        invokeRestart("muffleMessage")
      }
    ),
    error = function(error_condition) {
      report$n_failed_sections <- report$n_failed_sections + 1L
      if (is.function(report$error_sink)) {
        report$error_sink(error_condition)
      }
      failure <- class(error_condition)[1]
      .add_output_step(
        report,
        function(resolve) cat("  SECTION FAILED: ", failure, "\n", sep = "")
      )
    }
  )
  invisible(NULL)
}

# Decide what to hide, once. After it has run, registering another count is
# an error.
.prepare_report_for_printing <- function(report) {
  if (is.null(report$resolver)) {
    report$decision <- .decide_which_counts_to_hide(report)
    report$resolver <- .make_placeholder_resolver(report, report$decision)
  }
  invisible(report)
}

.print_report_legend <- function(report) {
  if (!report$hide_small_counts) {
    cat("Legend: all counts are exact; small counts are not hidden.\n")
    return(invisible(NULL))
  }
  cat(
    "Legend: \"<5\" = a count of 1-4; \"<suppr.>\" = a count of 5 or more, ",
    "suppressed so that no\n",
    "\"<5\" cell can be narrowed down from totals or other tables (a total is ",
    "suppressed\n",
    "whenever its group has a \"<5\" cell); 0 is printed as 0; \"-\" = ",
    "percentage withheld.\n",
    sep = ""
  )
}

.print_report_uncertified_note <- function(report) {
  .prepare_report_for_printing(report)
  n_uncertified <- length(report$decision$uncertified_ids)
  if (n_uncertified > 0L) {
    cat(
      "NOTE: ",
      n_uncertified,
      " \"<5\" cell(s) could not be certified against narrowing.\n",
      sep = ""
    )
  }
  invisible(NULL)
}

#' Print a report
#'
#' `render_report()` decides what to hide and prints everything, with a
#' legend; `print_report_section()` prints one section's output. Hiding is
#' decided over the whole report, so a section printed alone shows exactly
#' what it shows in the full report.
#'
#' @param report A report from [create_report()].
#' @return `render_report()`: the hiding decision, invisibly.
#'   `print_report_section()`: `NULL`, invisibly.
#' @examples
#' r <- create_report()
#' run_section(r, "Counts", add_line(r, "n = ", record_count(r, "n", 3)))
#' render_report(r)
#' print_report_section(r, "Counts")
#' @export
render_report <- function(report) {
  .prepare_report_for_printing(report)
  .print_report_legend(report)
  for (step in report$output_steps) {
    step$print_step(report$resolver)
  }
  .print_report_uncertified_note(report)
  report$is_rendered <- TRUE
  invisible(report$decision)
}

#' @rdname render_report
#' @param section_id The id given to [run_section()].
#' @param include_heading Whether to print the section's heading line (a
#'   Quarto document usually has its own).
#' @export
print_report_section <- function(
  report,
  section_id,
  include_heading = FALSE
) {
  .prepare_report_for_printing(report)
  known_ids <- unique(vapply(
    report$output_steps,
    function(step) step$section_id,
    character(1)
  ))
  if (!section_id %in% known_ids) {
    stop(
      "no report section with id '",
      section_id,
      "'; known ids: ",
      paste(stats::na.omit(known_ids), collapse = ", "),
      call. = FALSE
    )
  }
  for (step in report$output_steps) {
    is_in_section <- isTRUE(step$section_id == section_id)
    if (is_in_section && (include_heading || !step$is_heading)) {
      step$print_step(report$resolver)
    }
  }
  invisible(NULL)
}
```

`.store_provenance()` is referenced by `.add_count_table_impl()` but only called when `provenance` is non-NULL, which happens from Task 3 on. Add this stub to `R/provenance.R` now so the package loads (Task 3 keeps it unchanged):

```r
# Attach a provenance record to a registered count id.
.store_provenance <- function(report, id, provenance) {
  report$provenance[[id]] <- c(list(id = id), provenance)
  invisible(NULL)
}
```

- [ ] **Step 5: Document, run the tests**

Run: `Rscript -e 'roxygen2::roxygenise()'` then `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-report.R")'`
Expected: all ported tests plus the three new ones pass, 0 fail.

- [ ] **Step 6: Commit**

```bash
air format R/report.R R/report-suppression.R R/provenance.R tests/testthat/test-report.R
git add R/report.R R/report-suppression.R R/provenance.R tests/testthat/test-report.R NAMESPACE man/
git commit -m "feat(report): port sepsis_burn's disclosure-safe report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR"
```

---

### Task 3: Record provenance with every count

**Files:**
- Modify: `R/report.R` (`record_count()`, `record_unprinted_count()`, `add_count_table()`, `add_tabulation()`)
- Create: `tests/testthat/helper-report.R`
- Test: `tests/testthat/test-report-provenance.R`

**Interfaces:**
- Consumes: `.capture_provenance(call, env)`, `.store_provenance(report, id, provenance)` (Task 1/2), `.register_count()`, `.add_count_table_impl()` (Task 2).
- Produces: after any registering call, `report$provenance[[id]]` is a list with `id` plus the nine `.capture_provenance()` fields, for every printed and unprinted id. Test helper `source_user_code(lines, env = new.env())` returning `env` after sourcing `lines` from a temp file `user.R` with `keep.source = TRUE`.

- [ ] **Step 1: Write the test helper**

Create `tests/testthat/helper-report.R`:

```r
# Write `lines` to <tempdir>/user.R and source it with source references, the
# way a project's _targets.R sources its functions. Returns the environment.
source_user_code <- function(lines, env = new.env(), .local_envir = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = .local_envir)
  path <- file.path(dir, "user.R")
  writeLines(lines, path)
  source(path, local = env, keep.source = TRUE)
  env
}
```

- [ ] **Step 2: Write the failing tests**

Create `tests/testthat/test-report-provenance.R`:

```r
test_that("record_count records the statement and function that computed the value", {
  env <- source_user_code(c(
    "build <- function(x) {",
    "  r <- dctools::create_report()",
    "  dctools::add_line(r, \"n: \",",
    "    dctools::record_count(r, \"n\", length(x)))",
    "  r",
    "}"
  ))
  r <- env$build(1:12)
  p <- r$provenance[["n"]]
  expect_identical(p$id, "n")
  expect_identical(basename(p$file), "user.R")
  expect_identical(c(p$line_start, p$line_end), c(3L, 4L))
  expect_match(p$code, "record_count(r, \"n\", length(x))", fixed = TRUE)
  expect_identical(p$function_name, "build")
  expect_identical(c(p$function_line_start, p$function_line_end), c(1L, 6L))
  expect_identical(p$target, NA_character_)
})

test_that("a suffixed duplicate id gets its own provenance", {
  env <- source_user_code(c(
    "build <- function() {",
    "  r <- dctools::create_report()",
    "  dctools::record_count(r, \"n\", 5)",
    "  dctools::record_count(r, \"n\", 6)",
    "  r",
    "}"
  ))
  r <- env$build()
  expect_identical(r$provenance[["n"]]$line_start, 3L)
  expect_identical(r$provenance[["n_2"]]$line_start, 4L)
})

test_that("every table cell carries the table call's provenance, also via add_tabulation", {
  env <- source_user_code(c(
    "build <- function(x) {",
    "  r <- dctools::create_report()",
    "  dctools::add_tabulation(r, \"grp\", x, labels_from_code = TRUE)",
    "  r",
    "}"
  ))
  r <- env$build(c("a", "a", "b"))
  expect_setequal(names(r$provenance), c("grp.1", "grp.2"))
  for (p in r$provenance) {
    expect_identical(basename(p$file), "user.R")
    expect_identical(p$line_start, 3L)
    expect_identical(p$function_name, "build")
  }
})

test_that("record_unprinted_count records provenance too", {
  env <- source_user_code(c(
    "build <- function() {",
    "  r <- dctools::create_report()",
    "  dctools::record_unprinted_count(r, \"~gap\", 2)",
    "  r",
    "}"
  ))
  expect_identical(env$build()$provenance[["~gap"]]$line_start, 3L)
})

test_that("a count recorded inside run_section keeps the line of its own statement", {
  env <- source_user_code(c(
    "build <- function() {",
    "  r <- dctools::create_report()",
    "  dctools::run_section(r, \"S\", {",
    "    dctools::add_line(r, dctools::record_count(r, \"n\", 9))",
    "  })",
    "  r",
    "}"
  ))
  p <- env$build()$provenance[["n"]]
  expect_identical(p$line_start, 4L)
  expect_identical(p$function_name, "build")
})

test_that("code with no source file records NA source fields, not a crash", {
  env <- new.env()
  eval(
    parse(
      text = "f <- function() { r <- dctools::create_report(); dctools::record_count(r, 'n', 1); r }",
      keep.source = TRUE
    ),
    env
  )
  p <- env$f()$provenance[["n"]]
  expect_identical(p$file, NA_character_)
  expect_identical(p$function_name, "f")
})
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-report-provenance.R")'`
Expected: FAIL, `r$provenance[["n"]]` is NULL.

- [ ] **Step 4: Implement**

In `R/report.R`, replace the bodies of the four functions:

```r
record_count <- function(report, id, expr, protect = FALSE) {
  call <- sys.call()
  env <- parent.frame()
  id <- .register_count(report, id, expr, protect)
  .store_provenance(report, id, .capture_provenance(call, env))
  paste0("{{", id, "}}")
}
```

```r
record_unprinted_count <- function(report, id, expr) {
  call <- sys.call()
  env <- parent.frame()
  .stop_if_prepared(report)
  stopifnot(startsWith(id, "~"))
  report$unprinted_counts[id] <- as.numeric(expr)
  .store_provenance(report, id, .capture_provenance(call, env))
  invisible(id)
}
```

```r
add_count_table <- function(
  report,
  id,
  expr,
  protect = FALSE,
  labels_from_code = FALSE,
  total_id = NULL,
  max_levels = 30L
) {
  call <- sys.call()
  env <- parent.frame()
  .add_count_table_impl(
    report,
    id,
    expr,
    protect,
    labels_from_code,
    total_id,
    max_levels,
    provenance = .capture_provenance(call, env)
  )
}
```

```r
add_tabulation <- function(
  report,
  id,
  expr,
  protect = FALSE,
  labels_from_code = FALSE,
  total_id = NULL,
  max_levels = 30L
) {
  call <- sys.call()
  env <- parent.frame()
  tabulated <- table(expr, useNA = "ifany", dnn = NULL)
  .add_count_table_impl(
    report,
    id,
    tabulated,
    protect,
    labels_from_code,
    total_id,
    max_levels,
    provenance = .capture_provenance(call, env)
  )
}
```

`add_tabulation()` now lists its arguments instead of `...`: update its roxygen by deleting the `@param ...` line in the `add_count_table` block and changing `@rdname add_count_table` documentation to inherit (`add_tabulation` shares all parameters now).

- [ ] **Step 5: Run the tests**

Run: `Rscript -e 'roxygen2::roxygenise()'` then `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-report-provenance.R"); testthat::test_file("tests/testthat/test-report.R")'`
Expected: both files pass, 0 fail.

- [ ] **Step 6: Commit**

```bash
air format R/report.R tests/testthat/helper-report.R tests/testthat/test-report-provenance.R
git add R/report.R tests/testthat/helper-report.R tests/testthat/test-report-provenance.R man/
git commit -m "feat(report): record the source of every count

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR"
```

---

### Task 4: Bare-number guard

**Files:**
- Modify: `R/provenance.R` (add `.bare_numbers()`, `.check_bare_numbers()`)
- Modify: `R/report.R` (`add_line()`, `add_literal_line()`, `add_data_frame()`, `run_section()` call the guard)
- Test: `tests/testthat/test-bare-numbers.R`

**Interfaces:**
- Consumes: `.capture_provenance()`, `.srcref_lines()`.
- Produces: `.bare_numbers(text)` (character vector of distinct digit runs not inside a placeholder and not part of an identifier-like token); after a flagged call, `report$unprovenanced` gains one list with the nine `.capture_provenance()` fields of the adding call (never the number).

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-bare-numbers.R`:

```r
test_that(".bare_numbers skips placeholders and identifier-like tokens", {
  expect_identical(.bare_numbers("n = 12 of {{total}}"), "12")
  expect_identical(.bare_numbers("J7, death_28d and D13"), character(0))
  expect_identical(.bare_numbers("{{pct:a.1,a.2}}"), character(0))
  expect_setequal(.bare_numbers("1.5 and 3 and 3"), c("1.5", "3"))
  expect_identical(.bare_numbers(NA_character_), character(0))
})

guard_lines <- c(
  "build <- function(x, k) {",
  "  r <- dctools::create_report()",
  "  dctools::add_line(r, \"max: \", max(x))",
  "  dctools::add_line(r, \"within 48 hours\")",
  "  dctools::add_line(r, \"J7 and death_28d\")",
  "  dctools::add_line(r, \"n = \", dctools::record_count(r, \"n\", length(x)))",
  "  dctools::add_literal_line(r, paste(\"window\", k))",
  "  dctools::add_data_frame(r, data.frame(v = x[1:2]))",
  "  dctools::run_section(r, paste(\"Day\", k), dctools::add_line(r, \"ok\"))",
  "  dctools::run_section(r, \"Day 7\", dctools::add_line(r, \"ok\"))",
  "  dctools::add_tabulation(r, \"flag\", c(0, 1, 1))",
  "  r",
  "}"
)

test_that("numbers not written in the code of the adding call are flagged by location only", {
  env <- source_user_code(guard_lines)
  r <- env$build(c(31, 57, 64), k = 3)
  lines <- vapply(r$unprovenanced, function(p) p$line_start, integer(1))
  # max(x) (line 3), "window 3" (7), the data frame (8), the "Day 3" heading (9)
  expect_identical(sort(lines), c(3L, 7L, 8L, 9L))
  # Only the location is recorded: no text field holds the printed numbers.
  text_fields <- unlist(lapply(r$unprovenanced, function(p) p[c("file", "code", "function_name")]))
  expect_false(any(grepl("64|31|57|window 3|Day 3", text_fields)))
  expect_identical(basename(r$unprovenanced[[1]]$file), "user.R")
})

test_that("constants written in the code, placeholders and table labels pass", {
  env <- source_user_code(c(
    "build <- function() {",
    "  r <- dctools::create_report()",
    "  dctools::add_line(r, \"within 48 hours\")",
    "  dctools::run_section(r, \"Day 7\", dctools::add_line(r, \"n = \", dctools::record_count(r, \"n\", 40)))",
    "  dctools::add_tabulation(r, \"flag\", c(0, 1, 1))",
    "  r",
    "}"
  ))
  expect_length(env$build()$unprovenanced, 0L)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-bare-numbers.R")'`
Expected: FAIL, `.bare_numbers` not found.

- [ ] **Step 3: Implement**

Append to `R/provenance.R`:

```r
# Bare-number guard ------------------------------------------------------------
#
# A number printed without record_count() has no provenance. Text added to a
# report may contain digits only inside {{placeholders}}, as part of an
# identifier-like token (J7, death_28d, D13), or as constants written in the
# source of the call that added the text. Anything else is recorded by
# location only: the number itself may be a patient-level value.

.bare_numbers <- function(text) {
  text <- text[!is.na(text)]
  if (!length(text)) {
    return(character(0))
  }
  text <- gsub(.placeholder_pattern, " ", paste(text, collapse = "\n"))
  m <- gregexpr(
    "(?<![A-Za-z0-9_.])[0-9]+(\\.[0-9]+)?(?![A-Za-z0-9_])",
    text,
    perl = TRUE
  )
  unique(regmatches(text, m)[[1]])
}

.check_bare_numbers <- function(report, text, call, env) {
  numbers <- .bare_numbers(text)
  if (!length(numbers)) {
    return(invisible(FALSE))
  }
  srcref <- attr(call, "srcref")
  code <- if (is.null(srcref)) NA_character_ else .srcref_lines(srcref)
  if (all(numbers %in% .bare_numbers(code))) {
    return(invisible(FALSE))
  }
  report$unprovenanced[[length(report$unprovenanced) + 1L]] <-
    .capture_provenance(call, env)
  invisible(TRUE)
}
```

In `R/report.R`, add the guard to the text-adding functions:

```r
add_line <- function(report, ...) {
  text <- paste0(...)
  .check_bare_numbers(report, text, sys.call(), parent.frame())
  .add_output_step(report, function(resolve) cat(resolve(text), "\n", sep = ""))
}
```

```r
add_literal_line <- function(report, text) {
  force(text)
  .check_bare_numbers(report, text, sys.call(), parent.frame())
  .add_output_step(report, function(resolve) cat(text, "\n", sep = ""))
}
```

```r
add_data_frame <- function(report, data) {
  force(data)
  .check_bare_numbers(
    report,
    unlist(lapply(data, as.character), use.names = FALSE),
    sys.call(),
    parent.frame()
  )
  .add_output_step(report, function(resolve) {
    resolved <- data
    resolved[] <- lapply(resolved, function(column) {
      resolve(as.character(column))
    })
    print(resolved, row.names = FALSE)
  })
}
```

In `run_section()`, right after `force(section_id)`:

```r
  if (heading) {
    .check_bare_numbers(report, title, sys.call(), parent.frame())
  }
```

- [ ] **Step 4: Run the tests**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); for (f in c("test-bare-numbers.R", "test-report.R", "test-report-provenance.R")) testthat::test_file(file.path("tests/testthat", f))'`
Expected: all pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
air format R/provenance.R R/report.R tests/testthat/test-bare-numbers.R
git add R/provenance.R R/report.R tests/testthat/test-bare-numbers.R
git commit -m "feat(report): flag numbers printed without provenance

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR"
```

---

### Task 5: Git and hashing helpers, record stamp

**Files:**
- Create: `R/git.R`
- Create: `R/stamp.R`
- Test: `tests/testthat/test-stamp.R`

**Interfaces:**
- Produces (internal): `.git(repo, args)` (character stdout; error of class `dctools_git_error` on non-zero exit); `.git_ok(repo, args)` (logical); `.git_head(repo)`; `.git_root(repo)`; `.git_remote(repo)` (credentials stripped, `NA` when none); `.git_dirty_files(repo, exclude)` (paths from `git status --porcelain --untracked-files=all`, excluding those under `exclude`); `.repo_relative(path, root)`; `.is_absolute(path)`; `.sha256_file(path)` (`NA` when missing); `.object_path(store, name)`; `.strip_credentials(url)`; `.web_url(remote)`; `.as_chr(x)` (`NULL`/`NA` to `NA_character_`).
- Produces (exported): `stamp_record(targets_read, store = NULL, run_id = Sys.getenv("DCTOOLS_RUN_ID"), repo = ".")` printing a human line and `<!-- dctools-stamp {json} -->`, returning the stamp list (`run_id`, `sha`, `dctools_version`, `objects` named list of SHA-256) invisibly.
- Produces (internal): `.parse_stamps(path)` returning a list of stamp lists.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-stamp.R`:

```r
local_git_repo <- function(env = parent.frame()) {
  skip_if_not(nzchar(Sys.which("git")), "git is not installed")
  dir <- withr::local_tempdir(.local_envir = env)
  run <- function(...) system2("git", c("-C", dir, ...), stdout = TRUE, stderr = TRUE)
  run("init", "-q")
  run("config", "user.email", "test@example.com")
  run("config", "user.name", "test")
  writeLines("x", file.path(dir, "a.txt"))
  run("add", "-A")
  run("commit", "-q", "-m", "init")
  dir
}

test_that("git helpers read HEAD, dirty files and strip remote credentials", {
  repo <- local_git_repo()
  expect_match(.git_head(repo), "^[0-9a-f]{40}$")
  expect_identical(.git_dirty_files(repo, "docs/runs"), character(0))
  dir.create(file.path(repo, "docs", "runs"), recursive = TRUE)
  writeLines("{}", file.path(repo, "docs", "runs", "x.json"))
  writeLines("y", file.path(repo, "new file.txt"))
  expect_identical(.git_dirty_files(repo, "docs/runs"), "new file.txt")
  expect_identical(.git_remote(repo), NA_character_)
  system2("git", c("-C", repo, "remote", "add", "origin", "https://user:tok3n@example.com/o/r.git"))
  expect_identical(.git_remote(repo), "https://example.com/o/r.git")
  expect_error(.git(repo, c("cat-file", "-e", "deadbeef")), class = "dctools_git_error")
  expect_false(.git_ok(repo, c("cat-file", "-e", "deadbeef")))
})

test_that(".web_url turns remotes into browsable https URLs", {
  expect_identical(.web_url("git@github.com:o/r.git"), "https://github.com/o/r")
  expect_identical(.web_url("https://github.com/o/r.git"), "https://github.com/o/r")
  expect_identical(.web_url(NA_character_), NA_character_)
  expect_identical(.web_url("/local/path"), NA_character_)
})

test_that(".sha256_file matches digest and is NA for a missing file", {
  skip_if_not_installed("digest")
  f <- withr::local_tempfile(lines = "abc")
  expect_identical(.sha256_file(f), digest::digest(file = f, algo = "sha256"))
  expect_identical(.sha256_file(file.path(tempdir(), "no-such-file")), NA_character_)
})

test_that("stamp_record prints a readable line and a stamp that parses back", {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("digest")
  repo <- local_git_repo()
  store <- file.path(repo, "_targets")
  dir.create(file.path(store, "objects"), recursive = TRUE)
  saveRDS(1:3, file.path(store, "objects", "evidence"))
  out <- capture.output(
    stamp <- stamp_record("evidence", store = store, run_id = "20260101-000000", repo = repo)
  )
  expect_match(out[1], "^Run 20260101-000000 \\| commit [0-9a-f]{40} \\| dctools ")
  html <- withr::local_tempfile(fileext = ".html")
  writeLines(c("<p>before</p>", out, "<p>after</p>"), html)
  parsed <- .parse_stamps(html)
  expect_length(parsed, 1L)
  expect_identical(parsed[[1]]$run_id, "20260101-000000")
  expect_identical(parsed[[1]]$sha, .git_head(repo))
  expect_identical(
    parsed[[1]]$objects$evidence,
    .sha256_file(file.path(store, "objects", "evidence"))
  )
  expect_identical(stamp$objects$evidence, parsed[[1]]$objects$evidence)
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-stamp.R")'`
Expected: FAIL, `.git_head` not found.

- [ ] **Step 3: Implement `R/git.R`**

```r
# Git and hashing helpers (internal) -------------------------------------------
#
# The git CLI is used, not gert, so that every command the audit runs is one
# a person can run by hand to check it.

# Every argument is quoted: system2() pastes them into a shell command, and
# paths can hold spaces and pathspecs like "*.R" must reach git unexpanded.
.git <- function(repo, args) {
  out <- suppressWarnings(system2(
    "git",
    shQuote(c("-C", repo, args)),
    stdout = TRUE,
    stderr = FALSE
  ))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    stop(structure(
      class = c("dctools_git_error", "error", "condition"),
      list(
        message = paste0("git ", paste(args, collapse = " "), " failed"),
        call = NULL
      )
    ))
  }
  out
}

.git_ok <- function(repo, args) {
  tryCatch(
    {
      .git(repo, args)
      TRUE
    },
    dctools_git_error = function(e) FALSE
  )
}

.git_head <- function(repo) .git(repo, c("rev-parse", "HEAD"))

.git_root <- function(repo) {
  normalizePath(.git(repo, c("rev-parse", "--show-toplevel")), winslash = "/")
}

.strip_credentials <- function(url) sub("^(https?://)[^/@]+@", "\\1", url)

.git_remote <- function(repo) {
  url <- tryCatch(
    .git(repo, c("remote", "get-url", "origin")),
    dctools_git_error = function(e) character(0)
  )
  if (length(url)) .strip_credentials(url[[1]]) else NA_character_
}

.git_dirty_files <- function(repo, exclude) {
  status <- .git(repo, c("status", "--porcelain", "--untracked-files=all"))
  paths <- sub('^"(.*)"$', "\\1", sub("^.* -> ", "", substring(status, 4L)))
  prefix <- paste0(sub("/+$", "", exclude), "/")
  paths[!startsWith(paths, prefix)]
}

.is_absolute <- function(path) grepl("^(/|[A-Za-z]:[/\\\\])", path)

.repo_relative <- function(path, root) {
  if (.is_missing(path)) {
    return(NA_character_)
  }
  prefix <- paste0(sub("/+$", "", root), "/")
  if (startsWith(path, prefix)) substring(path, nchar(prefix) + 1L) else path
}

.sha256_file <- function(path) {
  if (.is_missing(path) || !file.exists(path) || dir.exists(path)) {
    return(NA_character_)
  }
  digest::digest(file = path, algo = "sha256")
}

.object_path <- function(store, name) file.path(store, "objects", name)

.web_url <- function(remote) {
  if (.is_missing(remote)) {
    return(NA_character_)
  }
  url <- sub("^git@([^:]+):", "https://\\1/", remote)
  url <- sub("^ssh://git@", "https://", url)
  url <- sub("\\.git$", "", url)
  if (grepl("^https?://", url)) url else NA_character_
}

.as_chr <- function(x) {
  if (.is_missing(x)) NA_character_ else as.character(x)
}
```

- [ ] **Step 4: Implement `R/stamp.R`**

```r
#' Stamp a rendered record with the run that produced it
#'
#' Called in a Quarto (or R Markdown) record built by a targets pipeline,
#' in a chunk with `results = "asis"`. Prints one human-readable line (run
#' id, git commit, dctools version) and an HTML comment holding the same
#' data plus the SHA-256 of each stored object the record read.
#' [write_run_ledger()] reads the comment back and the audit (check C7)
#' compares it with the ledger.
#'
#' @param targets_read Names of the targets the record reads.
#' @param store The targets store. Pass it explicitly from a Quarto
#'   document, which renders in its own directory (e.g.
#'   `here::here("_targets")`); defaults to the store of the current
#'   project.
#' @param run_id The run id; defaults to the `DCTOOLS_RUN_ID` environment
#'   variable that [run_targets_safe()] sets.
#' @param repo The git repository.
#' @return The stamp (a list with `run_id`, `sha`, `dctools_version`,
#'   `objects`), invisibly.
#' @seealso [write_run_ledger()], [audit_run()].
#' @examples
#' \dontrun{
#' stamp_record(c("eb_run_status", "eb_evidence_prep"),
#'              store = here::here("data", "processed", "_targets"))
#' }
#' @export
stamp_record <- function(
  targets_read,
  store = NULL,
  run_id = Sys.getenv("DCTOOLS_RUN_ID"),
  repo = "."
) {
  .require_pkgs(c("jsonlite", "digest"), "stamp_record")
  if (is.null(store)) {
    .require_pkgs("targets", "stamp_record")
    store <- targets::tar_config_get("store")
  }
  objects <- stats::setNames(
    lapply(targets_read, function(nm) .sha256_file(.object_path(store, nm))),
    targets_read
  )
  stamp <- list(
    run_id = run_id,
    sha = .git_head(repo),
    dctools_version = as.character(utils::packageVersion("dctools")),
    objects = objects
  )
  cat(
    "Run ",
    run_id,
    " | commit ",
    stamp$sha,
    " | dctools ",
    stamp$dctools_version,
    "\n\n",
    sep = ""
  )
  cat(
    "<!-- dctools-stamp ",
    as.character(jsonlite::toJSON(stamp, auto_unbox = TRUE, null = "null")),
    " -->\n",
    sep = ""
  )
  invisible(stamp)
}

.parse_stamps <- function(path) {
  if (!file.exists(path)) {
    return(list())
  }
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")
  found <- regmatches(
    text,
    gregexpr("<!-- dctools-stamp \\{.*?\\} -->", text, perl = TRUE)
  )[[1]]
  lapply(
    sub("^<!-- dctools-stamp (\\{.*\\}) -->$", "\\1", found),
    jsonlite::fromJSON,
    simplifyVector = FALSE
  )
}
```

- [ ] **Step 5: Run the tests**

Run: `Rscript -e 'roxygen2::roxygenise()'` then `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-stamp.R")'`
Expected: 4 tests pass, 0 fail.

- [ ] **Step 6: Commit**

```bash
air format R/git.R R/stamp.R tests/testthat/test-stamp.R
git add R/git.R R/stamp.R tests/testthat/test-stamp.R NAMESPACE man/
git commit -m "feat(ledger): git and hash helpers; stamp_record()

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR"
```

---

### Task 6: Ledger fixture and `write_run_ledger()`

**Files:**
- Create: `tests/testthat/helper-ledger-fixture.R`
- Create: `R/ledger.R`
- Test: `tests/testthat/test-ledger.R`

**Interfaces:**
- Consumes: Task 5 helpers, `.capture_provenance()` fields, `create_report()` / `record_count()`.
- Produces (exported): `write_run_ledger(path, run_id, reportable = character(0), links = NULL, extra_inputs = character(0), documents = character(0), records = character(0), store = NULL, script = NULL, repo = ".", requested = character(0), exit_code = NA_integer_)` writing `<path>/<run_id>.json` and returning its path invisibly. `links` is `NULL` or a data frame with character columns `decision_id`, `decision_status`, `target`, `role`.
- Produces (internal): `.load_reportable(store, names, read = NULL)` returning a named list of reports (hard stops: class `dctools_audit_unsafe_error`); `.read_meta(store)`; `.read_progress(store)`; `.spans_in_lines(lines, file)` (data frame `name`, `file`, `line_start`, `line_end`); `.function_spans(repo)`; `.dctools_engine()` returning `list(version, remote_sha)`.
- Ledger JSON (schema 1): `schema_version`; `run` {`run_id`, `written`, `requested`, `exit_code`}; `code` {`sha`, `remote`, `clean`, `dirty_files`, `r_version`, `renv_lock_sha256`, `dctools_version`, `dctools_remote_sha`}; `inputs` [{`path`, `sha256`, `targets_hash`}]; `documents` [{`path`, `sha256`}]; `targets` [{`name`, `type`, `format`, `command`, `depend`, `data`, `status`, `object_sha256`, `upstream`, `functions` [{`name`, `file`, `line_start`, `line_end`, `n_definitions`}]}]; `outdated`; `links` [{`decision_id`, `decision_status`, `target`, `role`}]; `reportable` [{`name`, `object_sha256`, `available`}]; `records` [{`path`, `sha256`, `stamps`}]; `provenance` [{`report`, `id`, the nine provenance fields with `file`/`function_file` repo-relative}]; `unprovenanced` [{`report`, the nine fields}]. Missing values are JSON `null`.
- Produces (tests): `ledger_fixture(fail = FALSE)` returning the path of a built, committed fixture project with a ledger at `docs/runs/20260101-000000.json` (built once per R session, under C9's mock engine `list(version = "9.9.9", remote_sha = "abc123")`); `copy_fixture(fail = FALSE)` returning a fresh copy in a temp dir; `fixture_run_id`; `local_engine(remote_sha = "abc123")` mocking `.dctools_engine()`; `edit_ledger(path, fn)`.

- [ ] **Step 1: Write the fixture helper**

Create `tests/testthat/helper-ledger-fixture.R`:

```r
# A small committed targets project with a run ledger, for the ledger and
# audit tests. Built once per session (one plain, one with a failing target)
# and copied per test so tests can corrupt their copy freely.

fixture_run_id <- "20260101-000000"
.fixture_cache <- new.env()

local_engine <- function(remote_sha = "abc123", env = parent.frame()) {
  testthat::local_mocked_bindings(
    .dctools_engine = function() list(version = "9.9.9", remote_sha = remote_sha),
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
  write.csv(data.frame(v = 1:12), file.path(proj, "data", "raw", "input values.csv"), row.names = FALSE)
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
  git <- function(...) system2("git", c("-C", proj, ...), stdout = TRUE, stderr = TRUE)
  git("init", "-q")
  git("config", "user.email", "test@example.com")
  git("config", "user.name", "test")
  git("remote", "add", "origin", "https://user:secret@example.com/o/r.git")
  git("add", "-A")
  git("commit", "-q", "-m", "fixture")
  res <- run_rscript(
    proj,
    "run.R",
    env = c(DCTOOLS_RUN_ID = fixture_run_id, FIXTURE_FAIL = if (fail) "1" else "0")
  )
  if (!fail && res$status != 0L) {
    stop("fixture pipeline failed: ", res$stderr)
  }
  # tar_network() and tar_outdated() source _targets.R in a child process,
  # which loads dctools through DCTOOLS_TEST_SRC.
  withr::local_envvar(DCTOOLS_TEST_SRC = dctools_src())
  testthat::with_mocked_bindings(
    withr::with_dir(proj, write_run_ledger(
      path = "docs/runs",
      run_id = fixture_run_id,
      reportable = "evidence",
      links = fixture_links(),
      documents = "decisions.yml",
      records = if (fail) character(0) else "output/record.html",
      store = "_targets",
      script = "_targets.R",
      exit_code = if (fail) 1L else 0L
    )),
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
```

- [ ] **Step 2: Write the failing tests**

Create `tests/testthat/test-ledger.R`:

```r
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
  expect_identical(l$documents[[1]]$sha256, .sha256_file(file.path(proj, "decisions.yml")))
  expect_false(grepl("secret", paste(readLines(fixture_ledger_path(proj)), collapse = "\n")))
})

test_that("the ledger records targets, their upstream targets and function spans", {
  skip_ledger_fixture()
  l <- read_fixture_ledger(ledger_fixture())
  t <- by_name(l$targets)
  expect_setequal(names(t), c("input_file", "values", "evidence", "record_file"))
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
    c("f <- function(x) {", "  g <- function() 1", "  x", "}", "h = function() NULL", "y <- 3"),
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
    .load_reportable("store", "x", read = fake(create_report(hide_small_counts = FALSE))),
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
    write_run_ledger("docs/new", "20260102-000000", reportable = "values",
                     store = "_targets", script = "_targets.R"),
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-ledger.R")'`
Expected: FAIL, `write_run_ledger` not found.

- [ ] **Step 4: Implement `R/ledger.R`**

```r
# Run ledger --------------------------------------------------------------------
#
# A PHI-free JSON index of one pipeline run: the code (git SHA), the inputs
# and decision documents (SHA-256), every target's metadata hashes and
# status, the stored objects' SHA-256, and where each reported value was
# computed. It holds no values; audit_run() checks it.

.dctools_engine <- function() {
  d <- utils::packageDescription("dctools")
  list(
    version = .as_chr(d$Version),
    remote_sha = if (is.null(d$RemoteSha)) NA_character_ else d$RemoteSha
  )
}

.abort_unsafe <- function(message) {
  stop(structure(
    class = c("dctools_audit_unsafe_error", "error", "condition"),
    list(message = message, call = NULL)
  ))
}

# The reportable targets' values. A target that was not built or stored NULL
# (an errored target under error = "null") is skipped; anything else that is
# not a masked dctools report stops, so nothing unsafe reaches a committed
# file.
.load_reportable <- function(store, names, read = NULL) {
  if (is.null(read)) {
    read <- function(name) {
      if (file.exists(.object_path(store, name))) {
        targets::tar_read_raw(name, store = store)
      } else {
        NULL
      }
    }
  }
  out <- list()
  for (nm in names) {
    obj <- read(nm)
    if (is.null(obj)) {
      next
    }
    if (!inherits(obj, "dctools_report")) {
      .abort_unsafe(sprintf("reportable target %s is not a dctools report", nm))
    }
    if (!isTRUE(obj$hide_small_counts)) {
      .abort_unsafe(sprintf(
        "reportable target %s prints small counts unmasked",
        nm
      ))
    }
    out[[nm]] <- obj
  }
  out
}

# Metadata without the error and warning text, which can hold row-level values.
.read_meta <- function(store) {
  meta <- as.data.frame(targets::tar_meta(store = store, targets_only = TRUE))
  keep <- intersect(
    c("name", "type", "format", "command", "depend", "data", "path"),
    names(meta)
  )
  meta[, keep, drop = FALSE]
}

.read_progress <- function(store) {
  as.data.frame(targets::tar_progress(fields = "progress", store = store))
}

.progress_of <- function(progress, name) {
  hit <- progress$progress[progress$name == name]
  if (length(hit)) hit[[1]] else NA_character_
}

.empty_spans <- function() {
  data.frame(
    name = character(0),
    file = character(0),
    line_start = integer(0),
    line_end = integer(0),
    stringsAsFactors = FALSE
  )
}

# Top-level `name <- function(...)` definitions in a file's lines.
.spans_in_lines <- function(lines, file) {
  exprs <- tryCatch(
    parse(text = lines, keep.source = TRUE),
    error = function(e) NULL
  )
  if (is.null(exprs) || !length(exprs)) {
    return(.empty_spans())
  }
  is_definition <- function(e) {
    is.call(e) &&
      (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
      is.symbol(e[[2]]) &&
      is.call(e[[3]]) &&
      identical(e[[3]][[1]], as.name("function"))
  }
  keep <- vapply(exprs, is_definition, logical(1))
  if (!any(keep)) {
    return(.empty_spans())
  }
  srcrefs <- attr(exprs, "srcref")[keep]
  data.frame(
    name = vapply(exprs[keep], function(e) as.character(e[[2]]), ""),
    file = file,
    line_start = vapply(srcrefs, function(s) as.integer(s[[1]]), 1L),
    line_end = vapply(srcrefs, function(s) as.integer(s[[3]]), 1L),
    stringsAsFactors = FALSE
  )
}

.function_spans <- function(repo) {
  files <- .git(repo, c("ls-files", "--", "*.R"))
  rows <- lapply(files, function(f) {
    .spans_in_lines(readLines(file.path(repo, f), warn = FALSE), f)
  })
  do.call(rbind, c(list(.empty_spans()), rows))
}

.span_of <- function(spans, name) {
  hit <- spans[spans$name == name, , drop = FALSE]
  if (!nrow(hit)) {
    return(list(
      name = name,
      file = NA_character_,
      line_start = NA_integer_,
      line_end = NA_integer_,
      n_definitions = 0L
    ))
  }
  list(
    name = name,
    file = hit$file[[1]],
    line_start = hit$line_start[[1]],
    line_end = hit$line_end[[1]],
    n_definitions = nrow(hit)
  )
}

.code_block <- function(repo, ledger_dir) {
  root <- .git_root(repo)
  exclude <- .repo_relative(
    normalizePath(ledger_dir, winslash = "/", mustWork = FALSE),
    root
  )
  dirty <- .git_dirty_files(repo, exclude)
  engine <- .dctools_engine()
  list(
    sha = .git_head(repo),
    remote = .git_remote(repo),
    clean = length(dirty) == 0L,
    dirty_files = I(dirty),
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    renv_lock_sha256 = .sha256_file(file.path(root, "renv.lock")),
    dctools_version = engine$version,
    dctools_remote_sha = engine$remote_sha
  )
}

.targets_block <- function(meta, progress, network, spans, store) {
  edges <- network$edges
  vertices <- network$vertices
  fn_names <- vertices$name[vertices$type == "function"]
  target_names <- vertices$name[vertices$type %in% c("stem", "pattern")]
  lapply(seq_len(nrow(meta)), function(i) {
    nm <- meta$name[[i]]
    from <- edges$from[edges$to == nm]
    list(
      name = nm,
      type = .as_chr(meta$type[[i]]),
      format = .as_chr(meta$format[[i]]),
      command = .as_chr(meta$command[[i]]),
      depend = .as_chr(meta$depend[[i]]),
      data = .as_chr(meta$data[[i]]),
      status = .progress_of(progress, nm),
      object_sha256 = .sha256_file(.object_path(store, nm)),
      upstream = I(sort(intersect(from, target_names))),
      functions = lapply(sort(intersect(from, fn_names)), function(f) {
        .span_of(spans, f)
      })
    )
  })
}

# One level of nesting removed, names dropped (a named list would be written
# as a JSON object, not an array), and list() rather than NULL when empty.
.flatten_list <- function(x) {
  x <- unlist(x, recursive = FALSE)
  if (is.null(x)) list() else unname(x)
}

.input_block <- function(meta, extra_inputs) {
  files <- meta[!is.na(meta$format) & meta$format == "file", , drop = FALSE]
  from_targets <- .flatten_list(lapply(seq_len(nrow(files)), function(i) {
    lapply(unlist(files$path[[i]]), function(p) {
      list(path = p, sha256 = .sha256_file(p), targets_hash = .as_chr(files$data[[i]]))
    })
  }))
  extra <- lapply(extra_inputs, function(p) {
    list(path = p, sha256 = .sha256_file(p), targets_hash = NA_character_)
  })
  c(from_targets, extra)
}

.links_block <- function(links) {
  if (is.null(links) || !nrow(links)) {
    return(list())
  }
  need <- c("decision_id", "decision_status", "target", "role")
  if (!all(need %in% names(links))) {
    cli::cli_abort("{.arg links} needs columns {.val {need}}.")
  }
  lapply(seq_len(nrow(links)), function(i) {
    lapply(stats::setNames(need, need), function(col) .as_chr(links[[col]][[i]]))
  })
}

.relative_provenance <- function(p, root) {
  p$file <- .repo_relative(p$file, root)
  p$function_file <- .repo_relative(p$function_file, root)
  p
}

.provenance_block <- function(reports, root) {
  .flatten_list(lapply(names(reports), function(nm) {
    lapply(unname(reports[[nm]]$provenance), function(p) {
      c(list(report = nm), .relative_provenance(p, root))
    })
  }))
}

.unprovenanced_block <- function(reports, root) {
  .flatten_list(lapply(names(reports), function(nm) {
    lapply(reports[[nm]]$unprovenanced, function(p) {
      c(list(report = nm), .relative_provenance(p, root))
    })
  }))
}

#' Write a run ledger
#'
#' After `targets::tar_make()`, writes `<path>/<run_id>.json`: a PHI-free
#' index of the run that [audit_run()] checks. It records the git commit
#' (and whether the working tree was clean), the SHA-256 of every file
#' input and decision document, each target's metadata hashes and status
#' and the SHA-256 of its stored object, the decision-to-target links, the
#' stamps of rendered records, and where each value in the reportable
#' reports was computed (file, lines, function, target). It never records a
#' value, an error message or a warning.
#'
#' Reportable targets must be masked dctools reports ([create_report()]);
#' anything else stops with class `dctools_audit_unsafe_error` before any
#' file is written. A reportable target that was not built, or stored
#' `NULL` after an error, is recorded as unavailable.
#'
#' Run it from the project root: relative paths in `extra_inputs`,
#' `documents` and `records` are read from the working directory.
#'
#' @param path Directory the ledger is written to (e.g. `"docs/runs"`);
#'   ignored by the clean-tree check.
#' @param run_id The run id (`YYYYMMDD-HHMMSS`).
#' @param reportable Names of targets whose values are dctools reports to
#'   index.
#' @param links `NULL` or a data frame with character columns
#'   `decision_id`, `decision_status`, `target` and `role` (`"args"` or
#'   `"evidence"`), one row per decision-target pair; a decision with no
#'   target has a row with `target = NA`.
#' @param extra_inputs Files the pipeline reads that are not
#'   `format = "file"` targets.
#' @param documents Decision and configuration files to hash.
#' @param records Rendered record files carrying a [stamp_record()] stamp.
#' @param store,script The targets store and script; default to the
#'   project's configuration.
#' @param repo The git repository.
#' @param requested Target names the run was restricted to, if any.
#' @param exit_code The runner's exit code so far.
#' @return The ledger's path, invisibly.
#' @seealso [audit_run()], [run_targets_safe()].
#' @examples
#' \dontrun{
#' write_run_ledger("docs/runs", "20261020-093000",
#'                  reportable = c("eb_run_status", "eb_evidence_prep"),
#'                  documents = "data/metadata/EARLYBURN/prep_decisions.yml")
#' }
#' @export
write_run_ledger <- function(
  path,
  run_id,
  reportable = character(0),
  links = NULL,
  extra_inputs = character(0),
  documents = character(0),
  records = character(0),
  store = NULL,
  script = NULL,
  repo = ".",
  requested = character(0),
  exit_code = NA_integer_
) {
  .require_pkgs(c("targets", "jsonlite", "digest"), "write_run_ledger")
  if (is.null(store)) {
    store <- targets::tar_config_get("store")
  }
  if (is.null(script)) {
    script <- targets::tar_config_get("script")
  }
  reports <- .load_reportable(store, reportable)
  root <- .git_root(repo)
  meta <- .read_meta(store)
  network <- targets::tar_network(
    targets_only = FALSE,
    outdated = FALSE,
    script = script,
    store = store,
    reporter = "silent"
  )
  ledger <- list(
    schema_version = 1L,
    run = list(
      run_id = run_id,
      written = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      requested = I(requested),
      exit_code = as.integer(exit_code)
    ),
    code = .code_block(repo, path),
    inputs = .input_block(meta, extra_inputs),
    documents = lapply(documents, function(p) {
      list(path = p, sha256 = .sha256_file(p))
    }),
    targets = .targets_block(
      meta,
      .read_progress(store),
      network,
      .function_spans(repo),
      store
    ),
    outdated = I(targets::tar_outdated(
      script = script,
      store = store,
      reporter = "silent"
    )),
    links = .links_block(links),
    reportable = lapply(reportable, function(nm) {
      list(
        name = nm,
        object_sha256 = .sha256_file(.object_path(store, nm)),
        available = !is.null(reports[[nm]])
      )
    }),
    records = lapply(records, function(p) {
      list(path = p, sha256 = .sha256_file(p), stamps = .parse_stamps(p))
    }),
    provenance = .provenance_block(reports, root),
    unprovenanced = .unprovenanced_block(reports, root)
  )
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  file <- file.path(path, paste0(run_id, ".json"))
  jsonlite::write_json(
    ledger,
    file,
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null",
    digits = NA
  )
  invisible(file)
}
```

- [ ] **Step 5: Run the tests**

Run: `Rscript -e 'roxygen2::roxygenise()'` then `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-ledger.R")'`
Expected: 7 tests pass, 0 fail. If `t$evidence$status` is `"built"` rather than `"completed"` (older targets), the installed targets reports the older label: change the expectation to `expect_true(t$evidence$status %in% c("built", "completed"))` and note it in the commit message.

- [ ] **Step 6: Commit**

```bash
air format R/ledger.R tests/testthat/helper-ledger-fixture.R tests/testthat/test-ledger.R
git add R/ledger.R tests/testthat/helper-ledger-fixture.R tests/testthat/test-ledger.R NAMESPACE man/
git commit -m "feat(ledger): write_run_ledger(), a PHI-free index of a run

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR"
```

---

### Task 7: `audit_run()` with checks C1-C3

**Files:**
- Create: `R/audit.R`
- Test: `tests/testthat/test-audit-core.R`

**Interfaces:**
- Consumes: Task 5 and 6 helpers; ledger schema 1.
- Produces (exported): `audit_run(ledger_path, store = NULL, script = NULL, repo = ".")` returning a data frame with columns `check`, `name`, `status` (`"PASS"`, `"FAIL"`, `"NOT EVALUATED"`), `n_evaluated`, `n_failed`, `detail` (list column of character vectors), one row per implemented check. (Tasks 8 and 9 extend it; the signature does not change.)
- Produces (internal): `.check_names`; `.items()`, `.item(item, ok, detail)`, `.bind_items(x)`, `.check_result(check, items, empty_reason)`; `.check_code(ledger, repo)`, `.check_store(ledger, store)`, `.check_fresh(ledger, script, store)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-audit-core.R`:

```r
audit_copy <- function(proj, ...) {
  withr::with_dir(proj, audit_run(
    fixture_ledger_path("."),
    store = "_targets",
    script = "_targets.R",
    ...
  ))
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
  expect_match(result$detail[result$check == "C1"][[1]], "differs from the recorded code", all = FALSE)
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
  cat("x", file = file.path(proj2, "_targets", "objects", "values"), append = TRUE)
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
  expect_match(result$detail[result$check == "C3"][[1]], "evidence", all = FALSE)
})

test_that(".check_result never passes an empty check", {
  r <- .check_result("C6", .items(), "no decision links in the ledger")
  expect_identical(r$status, "NOT EVALUATED")
  expect_identical(r$detail[[1]], "no decision links in the ledger")
  r2 <- .check_result("C6", .bind_items(list(.item("a", TRUE), .item("b", FALSE, "why"))), "")
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
  expect_false(file.exists(file.path(proj, "docs", "runs", paste0(fixture_run_id, ".md"))))
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-audit-core.R")'`
Expected: FAIL, `audit_run` not found.

- [ ] **Step 3: Implement `R/audit.R`**

```r
# Run audit ---------------------------------------------------------------------
#
# A fixed catalogue of checks (C1-C9) of a run ledger against git, the targets
# store and the files on disk. A check with nothing to evaluate is NOT
# EVALUATED, never PASS.

.check_names <- c(
  C1 = "Code",
  C2 = "Ledger matches store",
  C3 = "Fresh",
  C4 = "Complete",
  C5 = "Inputs",
  C6 = "Decisions",
  C7 = "Records",
  C8 = "Provenance",
  C9 = "Engine"
)

.items <- function(
  item = character(0),
  ok = logical(0),
  detail = character(0)
) {
  data.frame(item = item, ok = ok, detail = detail, stringsAsFactors = FALSE)
}

.item <- function(item, ok, detail = "") {
  ok <- isTRUE(ok)
  .items(item, ok, if (ok) "" else detail)
}

.bind_items <- function(x) {
  x <- Filter(Negate(is.null), x)
  if (!length(x)) .items() else do.call(rbind, x)
}

.check_result <- function(check, items, empty_reason) {
  n <- nrow(items)
  failed <- items[!items$ok, , drop = FALSE]
  status <- if (n == 0L) {
    "NOT EVALUATED"
  } else if (nrow(failed)) {
    "FAIL"
  } else {
    "PASS"
  }
  detail <- if (n == 0L) {
    empty_reason
  } else {
    paste0(failed$item, ": ", failed$detail)
  }
  out <- data.frame(
    check = check,
    name = .check_names[[check]],
    status = status,
    n_evaluated = n,
    n_failed = nrow(failed),
    stringsAsFactors = FALSE
  )
  out$detail <- list(detail)
  out
}

# Stack one-row check results; built column by column so the `detail` list
# column survives.
.bind_results <- function(results) {
  out <- data.frame(
    check = vapply(results, function(r) r$check, ""),
    name = vapply(results, function(r) r$name, ""),
    status = vapply(results, function(r) r$status, ""),
    n_evaluated = vapply(results, function(r) r$n_evaluated, 1L),
    n_failed = vapply(results, function(r) r$n_failed, 1L),
    stringsAsFactors = FALSE
  )
  out$detail <- lapply(results, function(r) r$detail[[1]])
  out
}

.int_or_na <- function(x) if (.is_missing(x)) NA_integer_ else as.integer(x)

# C1 Code -----------------------------------------------------------------------

.check_snippet <- function(p, show) {
  label <- paste0(p$report, ":", p$id)
  file <- .as_chr(p$file)
  if (is.na(file) || .is_absolute(file)) {
    return(.item(label, FALSE, "the source file is not in the repository"))
  }
  lines <- show(file)
  if (is.null(lines)) {
    return(.item(label, FALSE, sprintf("%s is not tracked at the run's commit", file)))
  }
  from <- .int_or_na(p$line_start)
  to <- .int_or_na(p$line_end)
  if (is.na(from) || is.na(to) || from < 1L || to > length(lines) || from > to) {
    return(.item(label, FALSE, "the line range is missing or outside the file"))
  }
  if (!identical(paste(lines[from:to], collapse = "\n"), .as_chr(p$code))) {
    return(.item(
      label,
      FALSE,
      sprintf("%s:%d-%d differs from the recorded code", file, from, to)
    ))
  }
  fn_file <- .as_chr(p$function_file)
  fn_lines <- if (is.na(fn_file)) NULL else show(fn_file)
  if (is.null(fn_lines)) {
    return(.item(label, FALSE, "the enclosing function has no tracked source"))
  }
  spans <- .spans_in_lines(fn_lines, fn_file)
  found <- spans$name == .as_chr(p$function_name) &
    spans$line_start == .int_or_na(p$function_line_start) &
    spans$line_end == .int_or_na(p$function_line_end)
  .item(
    label,
    any(found %in% TRUE),
    sprintf(
      "%s() is not defined at %s:%s-%s at the run's commit",
      .as_chr(p$function_name),
      fn_file,
      .as_chr(p$function_line_start),
      .as_chr(p$function_line_end)
    )
  )
}

.check_code <- function(ledger, repo) {
  sha <- .as_chr(ledger$code$sha)
  has_commit <- !is.na(sha) &&
    .git_ok(repo, c("cat-file", "-e", paste0(sha, "^{commit}")))
  items <- list(
    .item("commit", has_commit, "the run's commit is not in this repository"),
    .item(
      "clean tree",
      isTRUE(ledger$code$clean),
      "the run was made with uncommitted changes"
    )
  )
  if (has_commit) {
    cache <- new.env()
    show <- function(file) {
      if (!exists(file, envir = cache, inherits = FALSE)) {
        assign(
          file,
          tryCatch(
            .git(repo, c("show", paste0(sha, ":", file))),
            dctools_git_error = function(e) NULL
          ),
          envir = cache
        )
      }
      get(file, envir = cache, inherits = FALSE)
    }
    items <- c(items, lapply(ledger$provenance, .check_snippet, show = show))
  }
  .check_result("C1", .bind_items(items), "no commit recorded")
}

# C2 Ledger matches store -------------------------------------------------------

.check_store <- function(ledger, store) {
  meta <- .read_meta(store)
  progress <- .read_progress(store)
  in_ledger <- vapply(ledger$targets, function(t) .as_chr(t$name), "")
  items <- lapply(ledger$targets, function(t) {
    nm <- .as_chr(t$name)
    row <- meta[meta$name == nm, , drop = FALSE]
    if (!nrow(row)) {
      return(.item(nm, FALSE, "not in the store"))
    }
    same <- c(
      command = identical(.as_chr(t$command), .as_chr(row$command[[1]])),
      depend = identical(.as_chr(t$depend), .as_chr(row$depend[[1]])),
      data = identical(.as_chr(t$data), .as_chr(row$data[[1]])),
      status = identical(.as_chr(t$status), .progress_of(progress, nm)),
      object_sha256 = identical(
        .as_chr(t$object_sha256),
        .sha256_file(.object_path(store, nm))
      )
    )
    .item(nm, all(same), paste("differs:", paste(names(same)[!same], collapse = ", ")))
  })
  extra <- setdiff(meta$name, in_ledger)
  items <- c(items, lapply(extra, function(nm) {
    .item(nm, FALSE, "in the store but not in the ledger")
  }))
  .check_result("C2", .bind_items(items), "no targets in the ledger")
}

# C3 Fresh ----------------------------------------------------------------------

.check_fresh <- function(ledger, script, store) {
  recorded <- unlist(ledger$outdated)
  now <- targets::tar_outdated(script = script, store = store, reporter = "silent")
  .check_result(
    "C3",
    .bind_items(list(
      .item(
        "at run time",
        !length(recorded),
        paste("outdated:", paste(recorded, collapse = ", "))
      ),
      .item("now", !length(now), paste("outdated:", paste(now, collapse = ", ")))
    )),
    ""
  )
}

#' Audit a pipeline run against its ledger
#'
#' Checks a ledger written by [write_run_ledger()] against git, the targets
#' store and the files on disk, with a fixed catalogue of checks:
#'
#' * **C1 Code**: the commit exists, the run was made from a clean tree, and
#'   every recorded code snippet and function span equals the code at that
#'   commit.
#' * **C2 Ledger matches store**: every target's hashes, status and stored
#'   object match the store.
#' * **C3 Fresh**: nothing was outdated at run time or is now.
#' * **C4 Complete**: no target errored or was canceled.
#' * **C5 Inputs**: every input and document still has its recorded SHA-256.
#' * **C6 Decisions**: every decision links to a target that was built.
#' * **C7 Records**: every rendered record is unchanged and stamped with this
#'   run, its commit and the objects it read.
#' * **C8 Provenance**: every reported value has complete provenance, and no
#'   number was printed without it.
#' * **C9 Engine**: dctools was installed from a pushed commit, and the
#'   audit ran under the same dctools as the run.
#'
#' A check with nothing to evaluate is `"NOT EVALUATED"`, never `"PASS"`.
#' Before any check, a reportable target that is not a masked dctools report
#' stops the audit (class `dctools_audit_unsafe_error`) and nothing is
#' written. The audit is meant to run immediately after the run, against
#' the store that run produced.
#'
#' @param ledger_path Path to `<run_id>.json`.
#' @param store,script The targets store and script; default to the
#'   project's configuration.
#' @param repo The git repository.
#' @return A data frame, one row per check: `check`, `name`, `status`,
#'   `n_evaluated`, `n_failed`, `detail` (a list column of character
#'   vectors: the failed items, or why nothing was evaluated), with the
#'   overall verdict in `attr(, "verdict")`.
#' @seealso [write_run_ledger()], [run_targets_safe()].
#' @examples
#' \dontrun{
#' audit_run("docs/runs/20261020-093000.json")
#' }
#' @export
audit_run <- function(ledger_path, store = NULL, script = NULL, repo = ".") {
  .require_pkgs(c("targets", "jsonlite", "digest"), "audit_run")
  if (is.null(store)) {
    store <- targets::tar_config_get("store")
  }
  if (is.null(script)) {
    script <- targets::tar_config_get("script")
  }
  ledger <- jsonlite::read_json(ledger_path, simplifyVector = FALSE)
  reportable <- vapply(ledger$reportable, function(r) .as_chr(r$name), "")
  reports <- .load_reportable(store, reportable)
  .bind_results(list(
    .check_code(ledger, repo),
    .check_store(ledger, store),
    .check_fresh(ledger, script, store)
  ))
}
```

- [ ] **Step 4: Run the tests**

Run: `Rscript -e 'roxygen2::roxygenise()'` then `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-audit-core.R")'`
Expected: 8 tests pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
air format R/audit.R tests/testthat/test-audit-core.R
git add R/audit.R tests/testthat/test-audit-core.R NAMESPACE man/
git commit -m "feat(audit): audit_run() with checks C1-C3 and the unsafe-target stop

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR"
```

---

### Task 8: Checks C4-C9 and the verdict

**Files:**
- Modify: `R/audit.R`
- Test: `tests/testthat/test-audit-checks.R`

**Interfaces:**
- Consumes: Task 7's check helpers; `.load_reportable()`; `.dctools_engine()`; `.parse_stamps()`.
- Produces (internal): `.check_complete(store)`, `.check_inputs(ledger)`, `.check_decisions(ledger)`, `.check_records(ledger, store)`, `.check_provenance(ledger, reports)`, `.check_engine(ledger)`, `.verdict(status)`. `audit_run()` now returns nine rows (C1-C9) with `attr(result, "verdict")` set to `"PASS"`, `"FAIL"` or `"INCOMPLETE"`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-audit-checks.R`:

```r
audit_copy <- function(proj) {
  withr::with_dir(proj, audit_run(
    fixture_ledger_path("."),
    store = "_targets",
    script = "_targets.R"
  ))
}

status_of <- function(result, check) result$status[result$check == check]
detail_of <- function(result, check) result$detail[result$check == check][[1]]

test_that("the untouched fixture passes all nine checks", {
  skip_ledger_fixture()
  local_engine()
  result <- audit_copy(copy_fixture())
  expect_identical(result$check, paste0("C", 1:9))
  expect_identical(result$status, rep("PASS", 9), info = paste(unlist(result$detail), collapse = "; "))
  expect_identical(attr(result, "verdict"), "PASS")
})

test_that("C4 fails on an errored target; the unavailable report is skipped, not a stop", {
  skip_ledger_fixture()
  local_engine()
  result <- audit_copy(copy_fixture(fail = TRUE))
  expect_identical(status_of(result, "C4"), "FAIL")
  expect_match(detail_of(result, "C4"), "values: errored", all = FALSE)
  expect_identical(status_of(result, "C8"), "NOT EVALUATED")
  expect_identical(attr(result, "verdict"), "FAIL")
})

test_that("C5 fails when an input or a document changed", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  cat("13\n", file = file.path(proj, "data", "raw", "input values.csv"), append = TRUE)
  expect_match(detail_of(audit_copy(proj), "C5"), "input values.csv", all = FALSE)
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
  writeLines(sub("\"sha\":\"[0-9a-f]+\"", paste0("\"sha\":\"", strrep("1", 40), "\""), readLines(f)), f)
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
  ledger <- list(provenance = lapply(report$provenance, function(p) c(list(report = "ev"), p)))
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-audit-checks.R")'`
Expected: FAIL (only three checks returned; `.check_provenance` and `.verdict` not found).

- [ ] **Step 3: Implement**

Add to `R/audit.R`, before the `audit_run()` roxygen block:

```r
# C4 Complete -------------------------------------------------------------------

.check_complete <- function(store) {
  progress <- .read_progress(store)
  items <- lapply(seq_len(nrow(progress)), function(i) {
    .item(
      progress$name[[i]],
      !progress$progress[[i]] %in% c("errored", "canceled"),
      progress$progress[[i]]
    )
  })
  .check_result("C4", .bind_items(items), "no target progress recorded")
}

# C5 Inputs ---------------------------------------------------------------------

.check_inputs <- function(ledger) {
  files <- c(ledger$inputs, ledger$documents)
  items <- lapply(files, function(f) {
    path <- .as_chr(f$path)
    now <- .sha256_file(path)
    if (is.na(now)) {
      return(.item(path, FALSE, "missing"))
    }
    .item(path, identical(now, .as_chr(f$sha256)), "SHA-256 differs from the ledger")
  })
  .check_result("C5", .bind_items(items), "no inputs or documents in the ledger")
}

# C6 Decisions ------------------------------------------------------------------

.check_decisions <- function(ledger) {
  links <- ledger$links
  if (!length(links)) {
    return(.check_result("C6", .items(), "no decision links in the ledger"))
  }
  status <- stats::setNames(
    vapply(ledger$targets, function(t) .as_chr(t$status), ""),
    vapply(ledger$targets, function(t) .as_chr(t$name), "")
  )
  ids <- unique(vapply(links, function(l) .as_chr(l$decision_id), ""))
  items <- lapply(ids, function(id) {
    rows <- Filter(function(l) identical(.as_chr(l$decision_id), id), links)
    targets <- vapply(rows, function(l) .as_chr(l$target), "")
    bad <- vapply(targets, function(t) {
      if (is.na(t)) {
        return("no target")
      }
      if (!t %in% names(status)) {
        return(paste(t, "is not in the run"))
      }
      if (status[[t]] %in% c("errored", "canceled")) {
        return(paste(t, status[[t]]))
      }
      ""
    }, "")
    .item(id, all(bad == ""), paste(bad[bad != ""], collapse = "; "))
  })
  .check_result("C6", .bind_items(items), "no decision links in the ledger")
}

# C7 Records --------------------------------------------------------------------

.check_records <- function(ledger, store) {
  if (!length(ledger$records)) {
    return(.check_result("C7", .items(), "no records in the ledger"))
  }
  objects <- stats::setNames(
    vapply(ledger$targets, function(t) .as_chr(t$object_sha256), ""),
    vapply(ledger$targets, function(t) .as_chr(t$name), "")
  )
  items <- lapply(ledger$records, function(r) {
    path <- .as_chr(r$path)
    if (!identical(.sha256_file(path), .as_chr(r$sha256))) {
      return(.item(path, FALSE, "missing or changed since the run"))
    }
    stamps <- .parse_stamps(path)
    if (length(stamps) != 1L) {
      return(.item(path, FALSE, sprintf("%d stamps (expected 1)", length(stamps))))
    }
    s <- stamps[[1]]
    problems <- c(
      if (!identical(.as_chr(s$run_id), .as_chr(ledger$run$run_id))) "stamped with another run",
      if (!identical(.as_chr(s$sha), .as_chr(ledger$code$sha))) "stamped with another commit",
      unlist(lapply(names(s$objects), function(nm) {
        recorded <- .as_chr(s$objects[[nm]])
        if (!nm %in% names(objects)) {
          paste(nm, "is not in the ledger")
        } else if (
          !identical(recorded, objects[[nm]]) ||
            !identical(recorded, .sha256_file(.object_path(store, nm)))
        ) {
          paste(nm, "differs from what the record read")
        }
      }))
    )
    .item(path, !length(problems), paste(problems, collapse = "; "))
  })
  .check_result("C7", .bind_items(items), "no records in the ledger")
}

# C8 Provenance -----------------------------------------------------------------

.provenance_required <- c(
  "file",
  "line_start",
  "line_end",
  "code",
  "function_name",
  "function_file",
  "function_line_start",
  "function_line_end",
  "target"
)

# The ledger's paths are repo-relative, the report's absolute.
.same_path <- function(absolute, relative) {
  (is.na(absolute) && is.na(relative)) ||
    (!is.na(absolute) &&
      !is.na(relative) &&
      (identical(absolute, relative) || endsWith(absolute, paste0("/", relative))))
}

.same_provenance <- function(report_p, ledger_p) {
  if (is.null(ledger_p)) {
    return(FALSE)
  }
  fields <- c("line_start", "line_end", "code", "function_name",
              "function_line_start", "function_line_end", "target")
  all(vapply(fields, function(f) {
    identical(.as_chr(report_p[[f]]), .as_chr(ledger_p[[f]]))
  }, logical(1))) &&
    .same_path(.as_chr(report_p$file), .as_chr(ledger_p$file)) &&
    .same_path(.as_chr(report_p$function_file), .as_chr(ledger_p$function_file))
}

.check_provenance <- function(ledger, reports) {
  if (!length(reports)) {
    return(.check_result("C8", .items(), "no reportable report was available"))
  }
  in_ledger <- list()
  for (p in ledger$provenance) {
    in_ledger[[paste0(.as_chr(p$report), ":", .as_chr(p$id))]] <- p
  }
  items <- list()
  for (nm in names(reports)) {
    r <- reports[[nm]]
    for (id in c(names(r$counts), names(r$unprinted_counts))) {
      label <- paste0(nm, ":", id)
      p <- r$provenance[[id]]
      if (is.null(p)) {
        items[[length(items) + 1L]] <- .item(label, FALSE, "no provenance")
        next
      }
      missing <- .provenance_required[vapply(
        .provenance_required,
        function(f) .is_missing(p[[f]]),
        logical(1)
      )]
      if (length(missing)) {
        items[[length(items) + 1L]] <- .item(
          label,
          FALSE,
          paste("missing:", paste(missing, collapse = ", "))
        )
        next
      }
      items[[length(items) + 1L]] <- .item(
        label,
        .same_provenance(p, in_ledger[[label]]),
        "the ledger's provenance differs from the report's"
      )
    }
    for (u in r$unprovenanced) {
      items[[length(items) + 1L]] <- .item(
        paste0(nm, ":", basename(.as_chr(u$file)), ":", .as_chr(u$line_start)),
        FALSE,
        "a number was printed with no provenance"
      )
    }
  }
  .check_result("C8", .bind_items(items), "the reports hold no values")
}

# C9 Engine ---------------------------------------------------------------------

.check_engine <- function(ledger) {
  engine <- .dctools_engine()
  recorded_sha <- .as_chr(ledger$code$dctools_remote_sha)
  .check_result(
    "C9",
    .bind_items(list(
      .item(
        "installed from a pushed commit",
        !is.na(recorded_sha),
        "dctools has no RemoteSha: it was not installed from a pushed commit"
      ),
      .item(
        "same engine",
        !is.na(recorded_sha) &&
          identical(recorded_sha, .as_chr(engine$remote_sha)) &&
          identical(.as_chr(ledger$code$dctools_version), .as_chr(engine$version)),
        "the audit did not run under the same dctools as the run"
      )
    )),
    ""
  )
}

.verdict <- function(status) {
  if (all(status == "PASS")) {
    "PASS"
  } else if (any(status == "FAIL")) {
    "FAIL"
  } else {
    "INCOMPLETE"
  }
}
```

In `audit_run()`, replace the `.bind_results(list(...))` call with:

```r
  result <- .bind_results(list(
    .check_code(ledger, repo),
    .check_store(ledger, store),
    .check_fresh(ledger, script, store),
    .check_complete(store),
    .check_inputs(ledger),
    .check_decisions(ledger),
    .check_records(ledger, store),
    .check_provenance(ledger, reports),
    .check_engine(ledger)
  ))
  attr(result, "verdict") <- .verdict(result$status)
  result
```

- [ ] **Step 4: Run the tests**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-audit-checks.R"); testthat::test_file("tests/testthat/test-audit-core.R")'`
Expected: both files pass, 0 fail. If "the untouched fixture passes all nine checks" fails, its `info` lists the failing items: fix the check, not the test.

- [ ] **Step 5: Commit**

```bash
air format R/audit.R tests/testthat/test-audit-checks.R
git add R/audit.R tests/testthat/test-audit-checks.R
git commit -m "feat(audit): checks C4-C9 and the verdict

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR"
```

---

### Task 9: Human-readable audit and provenance pages

**Files:**
- Create: `R/audit-render.R`
- Modify: `R/audit.R` (`audit_run()` writes the two files)
- Test: `tests/testthat/test-audit-render.R`

**Interfaces:**
- Consumes: `audit_run()` result, ledger, reports.
- Produces: `audit_run()` writes `<dir of ledger>/<run_id>.md` and `<run_id>.provenance.md`; internal `.render_audit_md(ledger, result)`, `.render_provenance_md(ledger, reports)`, `.resolve_value(report, id)`, `.number_lines(code, start)`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-audit-render.R`:

```r
scrub <- function(x) {
  x <- gsub("[0-9a-f]{64}", "<sha256>", x)
  gsub("[0-9a-f]{40}", "<sha>", x)
}

run_fixture_audit <- function(proj) {
  withr::with_dir(proj, audit_run(
    fixture_ledger_path("."),
    store = "_targets",
    script = "_targets.R"
  ))
}

test_that("the audit page shows the verdict, one row per check and how to verify by hand", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  run_fixture_audit(proj)
  md <- readLines(file.path(proj, "docs", "runs", paste0(fixture_run_id, ".md")))
  expect_identical(md[1], paste0("# Run ", fixture_run_id, " audit: PASS"))
  expect_length(grep("^\\| C[1-9] \\|", md), 9L)
  expect_true(any(grepl("https://example.com/o/r/tree/", md, fixed = TRUE)))
  expect_false(any(grepl("secret", md)))
  expect_true(any(grepl("'data/raw/input values.csv'", md, fixed = TRUE)))
  expect_snapshot(cat(scrub(md), sep = "\n"))
})

test_that("failures are listed, ten at most per check", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  edit_ledger(fixture_ledger_path(proj), function(l) {
    l$links <- lapply(1:12, function(i) {
      list(decision_id = paste0("X", i), decision_status = "open", target = "nope", role = "evidence")
    })
    l
  })
  run_fixture_audit(proj)
  md <- readLines(file.path(proj, "docs", "runs", paste0(fixture_run_id, ".md")))
  expect_true("### C6 Decisions: FAIL" %in% md)
  expect_true("- ... and 2 more (see the ledger)" %in% md)
})

test_that("the provenance page shows each masked value with its code and a permalink", {
  skip_ledger_fixture()
  local_engine()
  proj <- copy_fixture()
  run_fixture_audit(proj)
  pm <- readLines(file.path(proj, "docs", "runs", paste0(fixture_run_id, ".provenance.md")))
  expect_true("## R/evidence.R" %in% pm)
  expect_true("### build_evidence() (lines 1-8)" %in% pm)
  expect_true(any(grepl("`evidence` / `n_values` = 12", pm, fixed = TRUE)))
  expect_true(any(grepl("`evidence` / `n_large` = 10", pm, fixed = TRUE)))
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-audit-render.R")'`
Expected: FAIL, no `.md` file written; `.resolve_value` not found.

- [ ] **Step 3: Implement `R/audit-render.R`**

```r
# Human-readable audit output ---------------------------------------------------
#
# <run_id>.md: the verdict, one row per check, what did not pass, and the
# commands that verify C1, C5 and C9 by hand. <run_id>.provenance.md: each
# reported value (masked as in its report) with the code that computed it,
# grouped by file and function. Neither holds anything the reports would not
# print.

.max_listed <- 10L

.render_audit_md <- function(ledger, result) {
  run_id <- .as_chr(ledger$run$run_id)
  sha <- .as_chr(ledger$code$sha)
  web <- .web_url(.as_chr(ledger$code$remote))
  commit <- if (is.na(web)) {
    sprintf("`%s`", sha)
  } else {
    sprintf("[`%s`](%s/tree/%s)", sha, web, sha)
  }
  out <- c(
    sprintf("# Run %s audit: %s", run_id, attr(result, "verdict")),
    "",
    sprintf(
      "- Commit: %s (%s)",
      commit,
      if (isTRUE(ledger$code$clean)) "clean" else "uncommitted changes"
    ),
    sprintf(
      "- dctools: %s (commit %s)",
      .as_chr(ledger$code$dctools_version),
      .as_chr(ledger$code$dctools_remote_sha)
    ),
    sprintf("- Ledger: `%s.json`; provenance: `%s.provenance.md`", run_id, run_id),
    "",
    "| Check | Name | Status | Evaluated | Failed |",
    "|---|---|---|---|---|",
    sprintf(
      "| %s | %s | %s | %d | %d |",
      result$check,
      result$name,
      result$status,
      result$n_evaluated,
      result$n_failed
    )
  )
  not_passed <- which(result$status != "PASS")
  if (length(not_passed)) {
    out <- c(out, "", "## Not passed")
    for (i in not_passed) {
      d <- result$detail[[i]]
      out <- c(
        out,
        "",
        sprintf("### %s %s: %s", result$check[i], result$name[i], result$status[i]),
        "",
        paste0("- ", utils::head(d, .max_listed))
      )
      if (length(d) > .max_listed) {
        out <- c(out, sprintf("- ... and %d more (see the ledger)", length(d) - .max_listed))
      }
    }
  }
  files <- c(
    vapply(ledger$inputs, function(x) .as_chr(x$path), ""),
    vapply(ledger$documents, function(x) .as_chr(x$path), "")
  )
  c(
    out,
    "",
    "## Verify by hand",
    "",
    "From the project root:",
    "",
    "```sh",
    sprintf("git cat-file -e %s^{commit} && echo 'C1: the commit exists'", sha),
    if (length(files)) {
      sprintf(
        "sha256sum %s   # C5: compare with \"sha256\" in %s.json",
        paste(shQuote(files), collapse = " "),
        run_id
      )
    },
    "Rscript -e 'utils::packageDescription(\"dctools\")$RemoteSha'   # C9: compare with the dctools commit above",
    "```"
  )
}

.resolve_value <- function(report, id) {
  if (is.null(report)) {
    return("(report not available)")
  }
  if (startsWith(id, "~")) {
    return("(not printed)")
  }
  .prepare_report_for_printing(report)
  report$resolver(paste0("{{", id, "}}"))
}

.number_lines <- function(code, start) {
  if (.is_missing(code)) {
    return("(no source)")
  }
  lines <- strsplit(code, "\n", fixed = TRUE)[[1]]
  sprintf("%d | %s", start + seq_along(lines) - 1L, lines)
}

.render_provenance_md <- function(ledger, reports) {
  run_id <- .as_chr(ledger$run$run_id)
  sha <- .as_chr(ledger$code$sha)
  web <- .web_url(.as_chr(ledger$code$remote))
  out <- c(
    sprintf("# Run %s: where each reported value came from", run_id),
    "",
    sprintf("Code at commit `%s`. Values are masked as in their reports.", sha)
  )
  prov <- ledger$provenance
  if (!length(prov)) {
    return(c(out, "", "No reported values."))
  }
  files <- vapply(prov, function(p) .as_chr(p$file), "")
  files[is.na(files)] <- "(no source file)"
  for (f in sort(unique(files))) {
    out <- c(out, "", paste0("## ", f))
    in_file <- prov[files == f]
    fns <- vapply(in_file, function(p) .as_chr(p$function_name), "")
    fns[is.na(fns)] <- "(no function)"
    for (fn in unique(fns)) {
      first <- in_file[[which(fns == fn)[1]]]
      out <- c(
        out,
        "",
        sprintf(
          "### %s() (lines %s-%s)",
          fn,
          .as_chr(first$function_line_start),
          .as_chr(first$function_line_end)
        )
      )
      for (p in in_file[fns == fn]) {
        start <- .int_or_na(p$line_start)
        end <- .int_or_na(p$line_end)
        link <- if (is.na(web) || f == "(no source file)" || is.na(start)) {
          ""
        } else {
          sprintf(" ([L%d-L%d](%s/blob/%s/%s#L%d-L%d))", start, end, web, sha, f, start, end)
        }
        out <- c(
          out,
          "",
          sprintf(
            "- `%s` / `%s` = %s%s",
            .as_chr(p$report),
            .as_chr(p$id),
            .resolve_value(reports[[.as_chr(p$report)]], .as_chr(p$id)),
            link
          ),
          "",
          "  ```r",
          paste0("  ", .number_lines(.as_chr(p$code), start)),
          "  ```"
        )
      }
    }
  }
  out
}

.write_audit_files <- function(ledger, result, reports, dir) {
  run_id <- .as_chr(ledger$run$run_id)
  writeLines(
    .render_audit_md(ledger, result),
    file.path(dir, paste0(run_id, ".md"))
  )
  writeLines(
    .render_provenance_md(ledger, reports),
    file.path(dir, paste0(run_id, ".provenance.md"))
  )
  invisible(NULL)
}
```

In `audit_run()` (R/audit.R), insert before the final `result`:

```r
  .write_audit_files(ledger, result, reports, dirname(ledger_path))
```

and add to its roxygen description: `Writes <run_id>.md (the verdict page) and <run_id>.provenance.md (each reported value with the code that computed it) next to the ledger.`

- [ ] **Step 4: Run the tests, accept the snapshots after reading them**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-audit-render.R")'`
Expected: pass, with two new snapshots in `tests/testthat/_snaps/audit-render.md`. Open that file and check by eye: one header line with `PASS`, nine table rows, no `## Not passed`, the verify-by-hand block; the provenance page lists `n_values` and `n_large` under `### build_evidence() (lines 1-8)` with code lines 4 and 5. Re-run: pass with no snapshot warnings.

- [ ] **Step 5: Commit**

```bash
air format R/audit-render.R R/audit.R tests/testthat/test-audit-render.R
git add R/audit-render.R R/audit.R tests/testthat/test-audit-render.R tests/testthat/_snaps/audit-render.md man/
git commit -m "feat(audit): human-readable audit and provenance pages

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR"
```

---

### Task 10: `run_targets_safe(ledger = )`

**Files:**
- Modify: `R/pipeline.R`
- Test: `tests/testthat/test-pipeline-ledger.R`

**Interfaces:**
- Consumes: `write_run_ledger()`, `audit_run()`, `.git_dirty_files()`.
- Produces: `run_targets_safe(args, status_targets, format_status, debug_root, private_root, keep, mask_below, run_id, ledger = NULL)`. `ledger` is `NULL` (unchanged behaviour) or a named list with any of `dir` (default `"docs/runs"`), `reportable`, `links`, `extra_inputs`, `documents`, `records`. With a ledger: a working tree with changes outside `dir` is a runner failure of class `dctools_runner_dirty_tree_error` (exit 2) before `tar_make()`; after the run, the ledger is written and audited, stdout gains an `== audit ==` block (`"<check> <name>: <status>"` lines, `verdict: <verdict>`, `ledger: <path>`), and the exit status is 3 when no target errored but the verdict is not `PASS`.

- [ ] **Step 1: Write the failing tests**

Create `tests/testthat/test-pipeline-ledger.R`:

```r
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
  for (check in c("C1 Code: PASS", "C2 Ledger matches store: PASS", "C5 Inputs: PASS",
                  "C7 Records: PASS", "C8 Provenance: PASS", "C9 Engine: FAIL")) {
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
  expect_identical(res$stdout, "runner failed: dctools_runner_dirty_tree_error\n")
  expect_false(dir.exists(file.path(proj, "_targets")))
})

test_that(".check_ledger_config fills defaults and rejects unknown elements", {
  cfg <- .check_ledger_config(list(reportable = "x"))
  expect_identical(cfg$dir, "docs/runs")
  expect_identical(cfg$reportable, "x")
  expect_error(.check_ledger_config(list(nope = 1)), class = "dctools_runner_usage_error")
  expect_error(.check_ledger_config("docs"), class = "dctools_runner_usage_error")
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-pipeline-ledger.R")'`
Expected: FAIL (`unused argument (ledger = ...)`, `.check_ledger_config` not found).

- [ ] **Step 3: Implement**

In `R/pipeline.R`, add before `# Exported: the runner`:

```r
.check_ledger_config <- function(ledger) {
  allowed <- c("dir", "reportable", "links", "extra_inputs", "documents", "records")
  if (!is.list(ledger) || is.null(names(ledger)) || !all(names(ledger) %in% allowed)) {
    .runner_abort(
      paste0("ledger must be a named list with elements from: ", paste(allowed, collapse = ", ")),
      "dctools_runner_usage_error"
    )
  }
  defaults <- list(
    dir = "docs/runs",
    reportable = character(0),
    extra_inputs = character(0),
    documents = character(0),
    records = character(0)
  )
  utils::modifyList(defaults, ledger)
}

.format_audit_summary <- function(result, ledger_file) {
  c(
    "== audit ==",
    sprintf("%s %s: %s", result$check, result$name, result$status),
    paste0("verdict: ", attr(result, "verdict")),
    paste0("ledger: ", ledger_file)
  )
}
```

Add the `ledger = NULL` argument to `run_targets_safe()` (last argument) and pass it through to `.run_targets_safe()` (add a matching last parameter `ledger`). Add to the roxygen of `run_targets_safe()`:

```r
#' @param ledger `NULL`, or a named list turning on the run ledger and audit
#'   (see [write_run_ledger()] and [audit_run()]): `dir` (default
#'   `"docs/runs"`), `reportable`, `links`, `extra_inputs`, `documents`,
#'   `records`. With a ledger, a working tree with uncommitted or untracked
#'   files outside `dir` is refused before the pipeline runs (runner failure
#'   `dctools_runner_dirty_tree_error`); after the run the ledger is written
#'   and audited, and stdout gains an `== audit ==` block with one line per
#'   check, the verdict and the ledger's path.
```

and change its `@return` to:

```r
#' @return The exit status, invisibly: `0L` when every target succeeded (and,
#'   with a ledger, the audit passed), `1L` when a target errored, `2L` when
#'   the runner itself failed, `3L` when no target errored but the audit's
#'   verdict was not `PASS`. On a runner failure stdout gets only
#'   `runner failed: <condition class>`, with the detail in `runner.log` when
#'   the debug directory could be made.
```

In `.run_targets_safe()`, right after the `format_status` check:

```r
  if (!is.null(ledger)) {
    ledger <- .check_ledger_config(ledger)
    dirty <- .git_dirty_files(".", ledger$dir)
    if (length(dirty)) {
      log_line("uncommitted or untracked files: ", paste(dirty, collapse = ", "))
      .runner_abort(
        "the working tree has uncommitted changes; commit them before a ledgered run",
        "dctools_runner_dirty_tree_error"
      )
    }
  }
```

Replace the last three lines of the `withCallingHandlers()` body (from `cat(out, sep = "\n")` to the `invisible(...)` line) with:

```r
      cat(out, sep = "\n")
      status <- if (!made || any(progress$progress == "errored")) 1L else 0L
      if (!is.null(ledger)) {
        ledger_file <- write_run_ledger(
          path = ledger$dir,
          run_id = run_id,
          reportable = ledger$reportable,
          links = ledger$links,
          extra_inputs = ledger$extra_inputs,
          documents = ledger$documents,
          records = ledger$records,
          requested = selected,
          exit_code = status
        )
        audit <- audit_run(ledger_file)
        cat(.format_audit_summary(audit, ledger_file), sep = "\n")
        if (status == 0L && !identical(attr(audit, "verdict"), "PASS")) {
          status <- 3L
        }
      }
      .prune_debug_runs(debug_root, keep = keep)
      invisible(status)
```

- [ ] **Step 4: Run the tests**

Run: `Rscript -e 'roxygen2::roxygenise()'` then `Rscript -e 'pkgload::load_all(quiet = TRUE); testthat::test_file("tests/testthat/test-pipeline-ledger.R"); testthat::test_file("tests/testthat/test-pipeline-runner.R")'`
Expected: both files pass, 0 fail (the existing runner tests are unchanged by `ledger = NULL`).

- [ ] **Step 5: Commit**

```bash
air format R/pipeline.R tests/testthat/test-pipeline-ledger.R
git add R/pipeline.R tests/testthat/test-pipeline-ledger.R man/
git commit -m "feat(pipeline): run_targets_safe(ledger =) writes and audits a run ledger

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR"
```

---

### Task 11: Dependencies, reference index, docs, full check

**Files:**
- Modify: `DESCRIPTION`, `_pkgdown.yml`, `NEWS.md`, `ROADMAP.md`, `memos/decisions.md`, `STATUS.md`, `memos/specs/2026-10-20-run-ledger-design.md`

- [ ] **Step 1: DESCRIPTION**

Add `callr` and `digest` to `Suggests` (alphabetical; `fs` is already in Imports, `jsonlite`, `processx`, `targets`, `pkgload`, `withr` already in Suggests).

- [ ] **Step 2: `_pkgdown.yml`**

After the `Disclosure-safe targets pipelines` section add:

```yaml
  - title: Disclosure-safe reports
    contents:
      - create_report
      - record_count
      - record_unprinted_count
      - add_line
      - add_count_table
      - declare_linear_relation
      - declare_sum_relation
      - run_section
      - render_report
  - title: Run ledger and audit
    contents:
      - write_run_ledger
      - audit_run
      - stamp_record
```

(`add_literal_line`, `add_data_frame`, `add_tabulation` and `print_report_section` share the topics listed via `@rdname`.)

- [ ] **Step 3: NEWS.md** (under `# dctools (development version)`, at the top)

```markdown
* Disclosure-safe reports, ported from sepsis_burn: `create_report()`,
  `record_count()`, `record_unprinted_count()`, `add_line()`,
  `add_literal_line()`, `add_data_frame()`, `add_count_table()`,
  `add_tabulation()`, `declare_linear_relation()`, `declare_sum_relation()`,
  `run_section()`, `render_report()`, `print_report_section()`. Every count
  records the source lines and function that computed it; numbers printed
  without `record_count()` are flagged.
* Run ledger and audit: `write_run_ledger()` writes a PHI-free JSON index of a
  targets run; `audit_run()` checks it (C1-C9: code, store, freshness,
  completeness, inputs, decisions, records, provenance, engine) and writes a
  one-page verdict and a provenance page; `stamp_record()` stamps rendered
  records. `run_targets_safe(ledger = )` refuses a dirty working tree, then
  writes and audits a ledger after every run (new exit status 3: the audit
  did not pass).
```

- [ ] **Step 4: ROADMAP.md section 8**

Add after the `compare_targets()` line:

```markdown
- [x] `write_run_ledger()` / `audit_run()` / `stamp_record()` + the disclosure-safe report (`create_report()`, `record_count()`, ...) — mechanical audit of a targets run: every reported number traced to committed code, hashed inputs and an up-to-date store (checks C1-C9), with a one-page verdict and a provenance page. Spec: `memos/specs/2026-10-20-run-ledger-design.md`. First consumer: sepsis_burn
```

- [ ] **Step 5: memos/decisions.md** (newest at the top, after the template comment's position per the file's convention)

```markdown
## 2026-10-20 - Run ledger: the audit, not the analyst, vouches for reported numbers
**Decision:** Reported numbers enter reports only through `record_count()` and friends, which record their source lines; a PHI-free ledger indexes each run; `audit_run()` checks it with a fixed catalogue (C1-C9) that projects cannot shorten and that is tested to fail on corrupted input. The audit runs once, right after the run.
**Why:** An agent-run analysis must be checkable without trusting the agent: its claims are citations into an audit file it cannot write, and the audit is reproducible from git, the store and the inputs.
**Alternatives rejected:** a claims file written by the agent (it could fabricate both claim and ledger); verification as a target (a target cannot audit the run it belongs to); snapshots only (they show change, not which code produced it); replaying old runs (needs hash-stable objects; not needed when every run is audited immediately).
**Links:** `memos/specs/2026-10-20-run-ledger-design.md`, `memos/plans/2026-10-20-run-ledger.md`.
```

- [ ] **Step 6: Spec sync**

In `memos/specs/2026-10-20-run-ledger-design.md`: in the 3.1 table and everywhere else, `add_count()` becomes `record_count()` and `add_unprinted_count()` becomes `record_unprinted_count()`; drop `threshold = 5L` from `create_report()`; in section 6 replace "The `sepsis_burn` runner, hook, record changes and call-site migration (its own spec)." with "The sepsis_burn hook, record changes and call-site migration (its own spec). The runner integration is `run_targets_safe(ledger = )` in dctools."; add under 3.1: "A failed `run_section()` prints only the error's class." and under 5: "`jsonlite` and `digest` are in Suggests, guarded like the rest of `R/pipeline.R`; `quarto` is not needed."

- [ ] **Step 7: STATUS.md**

Set `**Updated:** 2026-10-20`; add to `## Recent progress` at the top:

```markdown
- 2026-10-20 — run ledger and audit (`write_run_ledger()`, `audit_run()`, `stamp_record()`) and the disclosure-safe report ported from sepsis_burn with per-count provenance; `run_targets_safe(ledger =)`. Next: sepsis_burn integration spec (migrate its evidence code to `record_count()`, stamp its decision records, guard hook on `docs/runs/`).
```

- [ ] **Step 8: Full verification**

Run, in order:

```bash
Rscript -e 'roxygen2::roxygenise()'
air format .
LC_ALL=C grep -rnP '[^\x00-\x7F]' R/ tests/ || echo ASCII-OK
Rscript -e 'testthat::test_local(".")'
Rscript -e 'rcmdcheck::rcmdcheck(args = c("--no-manual", "--as-cran"), error_on = "warning")'
```

Expected: `ASCII-OK`; all tests pass, 0 failures (subprocess tests may skip only if a Suggests package is missing: report any skip); `rcmdcheck` 0 errors, 0 warnings. Report the NOTE count and each NOTE's text.

- [ ] **Step 9: Commit**

```bash
git add DESCRIPTION _pkgdown.yml NEWS.md ROADMAP.md memos/ STATUS.md man/ NAMESPACE
git commit -m "docs: run ledger and audit in NEWS, ROADMAP, decisions, reference index

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013HmBReTUKVch3q734kWAUR"
```
