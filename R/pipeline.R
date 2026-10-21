# Disclosure-safe targets pipeline -------------------------------------------
#
# Two halves share one contract, the per-target status sidecar
# `<debug_dir>/<target>.status.json`:
#   - inside targets, capture_target_debug() writes full error detail to a
#     debug bundle and a pattern-checked sidecar;
#   - run_targets_safe() runs tar_make() with all output diverted to the debug
#     directory and prints only an allowlist built from the progress table and
#     the sidecars.

.safe_name_pattern <- "^[A-Za-z][A-Za-z0-9_.]{0,63}$"
.safe_status_pattern <- "^[A-Za-z0-9_.,]{1,64}$"
.safe_count_name_pattern <- "^[A-Za-z][A-Za-z0-9_]{0,63}$"

.require_pkgs <- function(pkgs, fn) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    cli::cli_abort(
      "{.fn {fn}} requires the {.pkg {missing}} package{?s}.",
      class = "dctools_missing_package_error"
    )
  }
}

.is_safe_name <- function(x) {
  is.character(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    grepl(.safe_name_pattern, x)
}

# `path` must lie under a `private_root` path segment (e.g. ".../data/processed/..."),
# the git-ignored home of row-level data.
.require_private_path <- function(path, private_root) {
  norm <- function(x) sub("/+$", "", gsub("\\\\", "/", x))
  root <- norm(private_root)
  pattern <- paste0(
    "(^|/)",
    gsub("([.|()\\^{}+$*?\\[\\]])", "\\\\\\1", root),
    "(/|$)"
  )
  if (!nzchar(root) || !grepl(pattern, norm(path))) {
    cli::cli_abort(
      "Refusing to write debug detail outside {.path {private_root}}: {.path {path}}.",
      class = "dctools_unsafe_path_error"
    )
  }
  invisible(path)
}

# Status sidecar --------------------------------------------------------------

.debug_status_path <- function(debug_dir, target_name) {
  file.path(debug_dir, paste0(target_name, ".status.json"))
}

.safe_status_string <- function(x) {
  if (
    is.character(x) &&
      length(x) == 1L &&
      !is.na(x) &&
      grepl(.safe_status_pattern, x)
  ) {
    x
  } else {
    NULL
  }
}

.safe_status_counts <- function(counts) {
  out <- stats::setNames(list(), character(0))
  if (!is.list(counts) || is.null(names(counts))) {
    return(out)
  }
  for (nm in names(counts)) {
    if (is.na(nm) || !grepl(.safe_count_name_pattern, nm)) {
      next
    }
    v <- counts[[nm]]
    if (length(v) != 1L || !(is.numeric(v) || is.logical(v)) || is.na(v)) {
      next
    }
    iv <- suppressWarnings(as.integer(v))
    if (!is.na(iv)) out[[nm]] <- iv
  }
  out
}

# Each field comes only from a `safe_class` condition and must match a strict
# pattern; anything else becomes null / empty.
.write_debug_status <- function(
  debug_dir,
  target_name,
  status,
  condition,
  n_warnings,
  safe_class
) {
  safe <- !is.null(condition) && inherits(condition, safe_class)
  cls <- if (is.null(condition)) character(0) else class(condition)
  fields <- list(
    target = target_name,
    status = status,
    class = I(cls[grepl(.safe_name_pattern, cls)]),
    code = if (safe) .safe_status_string(condition[["code"]]),
    counts = if (safe) {
      .safe_status_counts(condition[["counts"]])
    } else {
      stats::setNames(list(), character(0))
    },
    context = if (safe) .safe_status_string(condition[["context"]]),
    n_warnings = as.integer(n_warnings)
  )
  jsonlite::write_json(
    fields,
    .debug_status_path(debug_dir, target_name),
    auto_unbox = TRUE,
    null = "null",
    pretty = TRUE
  )
}

# Debug bundle ----------------------------------------------------------------

# The payload in full for the bundle's .txt (a private file, never printed):
# data frames and vectors whole up to `max_rows`, named lists element by
# element, anything else via str().
.format_debug_payload <- function(debug, max_rows = 1000L) {
  if (is.null(debug)) {
    return("NULL")
  }
  op <- options(max.print = .Machine$integer.max)
  on.exit(options(op))
  if (is.data.frame(debug)) {
    out <- utils::capture.output(
      print(as.data.frame(utils::head(debug, max_rows)), row.names = FALSE)
    )
    if (nrow(debug) > max_rows) {
      out <- c(
        out,
        sprintf("... %d more row(s) in the .rds", nrow(debug) - max_rows)
      )
    }
    return(c(sprintf("<%d row(s)>", nrow(debug)), out))
  }
  if (is.atomic(debug)) {
    out <- utils::capture.output(print(utils::head(debug, max_rows)))
    if (length(debug) > max_rows) {
      out <- c(
        out,
        sprintf("... %d more value(s) in the .rds", length(debug) - max_rows)
      )
    }
    return(out)
  }
  if (is.list(debug) && !is.null(names(debug)) && all(nzchar(names(debug)))) {
    return(unlist(
      lapply(names(debug), function(nm) {
        c(paste0("$", nm), .format_debug_payload(debug[[nm]], max_rows))
      }),
      use.names = FALSE
    ))
  }
  utils::capture.output(utils::str(debug, list.len = 50))
}

.write_debug_bundle <- function(
  debug_dir,
  target_name,
  condition,
  trace,
  warnings
) {
  bundle <- list(
    target = target_name,
    time = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    message = conditionMessage(condition),
    call = conditionCall(condition),
    class = class(condition),
    code = condition[["code"]],
    counts = condition[["counts"]],
    context = condition[["context"]],
    debug = condition[["debug"]],
    trace = trace,
    warnings = warnings
  )
  saveRDS(bundle, file.path(debug_dir, paste0(target_name, ".rds")))
  code <- condition[["code"]]
  txt <- c(
    paste0("target: ", target_name),
    paste0("class: ", paste(class(condition), collapse = ", ")),
    paste0("code: ", if (is.null(code)) "" else paste(code, collapse = " ")),
    "message:",
    conditionMessage(condition),
    "warnings:",
    warnings,
    "debug payload:",
    .format_debug_payload(condition[["debug"]]),
    "trace:",
    utils::capture.output(print(trace))
  )
  writeLines(txt, file.path(debug_dir, paste0(target_name, ".txt")))
}

# Exported: in-target capture ---------------------------------------------------

#' Signal an error whose summary fields are safe to print
#'
#' Raises an error of class `c(class, "dctools_safe_error", "error",
#' "condition")` that carries, besides its message, the fields
#' [capture_target_debug()] copies into a target's status sidecar (`code`,
#' `counts`, `context`) and a `debug` payload that goes only to the private
#' debug bundle. The message and `debug` may hold row-level detail; `code`,
#' `counts` names and `context` must not, and are pattern-checked again when the
#' sidecar is written.
#'
#' @param message The error message (written to the debug bundle, never
#'   printed by [run_targets_safe()]).
#' @param code An identifier-shaped error code (letters, digits, `_`, `.`;
#'   starting with a letter; at most 64 characters).
#' @param counts A named list of integer counts. Names must be identifiers;
#'   values are coerced with [as.integer()].
#' @param context Optional short identifier-shaped context string.
#' @param debug Optional payload of any type (e.g. the offending rows), kept
#'   only in the debug bundle.
#' @param class Additional condition classes, prepended.
#' @return Does not return; signals the error.
#' @seealso [capture_target_debug()], [run_targets_safe()].
#' @examples
#' e <- tryCatch(
#'   abort_safe("3 rows lack an ID", code = "D2_missing_id", counts = list(n = 3)),
#'   error = identity
#' )
#' e$code
#' @export
abort_safe <- function(
  message,
  code,
  counts = list(),
  context = NULL,
  debug = NULL,
  class = character(0)
) {
  if (!.is_safe_name(code)) {
    cli::cli_abort("{.arg code} must be a single identifier-shaped string.")
  }
  cnd <- structure(
    class = c(class, "dctools_safe_error", "error", "condition"),
    list(
      message = message,
      call = NULL,
      code = code,
      counts = suppressWarnings(lapply(counts, as.integer)),
      context = context,
      debug = debug
    )
  )
  stop(cnd)
}

#' The debug directory set by the safe runner
#'
#' @return The value of the `DCTOOLS_DEBUG_DIR` environment variable, which
#'   [run_targets_safe()] sets to this run's debug directory; `""` when unset
#'   (e.g. a plain `targets::tar_make()`).
#' @seealso [capture_target_debug()].
#' @examples
#' get_debug_dir()
#' @export
get_debug_dir <- function() Sys.getenv("DCTOOLS_DEBUG_DIR")

#' Capture a target's errors and warnings into a private debug directory
#'
#' Wrap a target's command in this so that, when the safe runner is running
#' the pipeline, no detail reaches the console:
#' * on error, the full condition (message, call, class, trace, `debug`
#'   payload, warnings so far) is written to `<target_name>.rds` and
#'   `<target_name>.txt`, a status sidecar `<target_name>.status.json` is
#'   written, and the error is re-raised;
#' * warnings are muffled, written to `warnings_<target_name>.txt`, and counted
#'   in the sidecar.
#'
#' The sidecar is what [run_targets_safe()] prints from. Its `code`, `counts`
#' and `context` are taken only from a condition inheriting `safe_class` (see
#' [abort_safe()]) and only when they match identifier/integer patterns; for any
#' other condition the sidecar records just its class.
#'
#' With an empty `debug_dir` the expression is evaluated as is, so the same
#' pipeline still runs under a plain `targets::tar_make()`.
#'
#' @param expr The target's command.
#' @param target_name The target's name (an identifier); names the files.
#' @param debug_dir The debug directory. Defaults to [get_debug_dir()].
#' @param safe_class The condition class whose `code`/`counts`/`context` may be
#'   copied into the sidecar.
#' @param private_root A path segment the debug directory must lie under
#'   (default `"data/processed"`); anything else is refused before writing.
#' @return The value of `expr`.
#' @seealso [run_targets_safe()], [abort_safe()], [read_debug_status()].
#' @examples
#' dir <- file.path(tempdir(), "data", "processed", "debug", "example")
#' capture_target_debug({
#'   warning("kept out of the console")
#'   42
#' }, "answer", dir)
#' list.files(dir)
#' @export
capture_target_debug <- function(
  expr,
  target_name,
  debug_dir = get_debug_dir(),
  safe_class = "dctools_safe_error",
  private_root = "data/processed"
) {
  if (!nzchar(debug_dir)) {
    return(expr)
  }
  if (!.is_safe_name(target_name)) {
    cli::cli_abort("{.arg target_name} must be an identifier.")
  }
  .require_pkgs("jsonlite", "capture_target_debug")
  .require_private_path(debug_dir, private_root)
  dir.create(debug_dir, recursive = TRUE, showWarnings = FALSE)
  warnings <- character(0)
  trace <- NULL
  result <- tryCatch(
    withCallingHandlers(
      expr,
      error = function(e) trace <<- rlang::trace_back(),
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      # A failure while recording must never replace the original error.
      try(
        suppressWarnings(.write_debug_status(
          debug_dir,
          target_name,
          "error",
          e,
          length(warnings),
          safe_class
        )),
        silent = TRUE
      )
      try(
        suppressWarnings(.write_debug_bundle(
          debug_dir,
          target_name,
          e,
          trace,
          warnings
        )),
        silent = TRUE
      )
      stop(e)
    }
  )
  if (length(warnings)) {
    writeLines(
      warnings,
      file.path(debug_dir, paste0("warnings_", target_name, ".txt"))
    )
    .write_debug_status(
      debug_dir,
      target_name,
      "ok",
      NULL,
      length(warnings),
      safe_class
    )
  }
  result
}

#' A sink that writes caught conditions to numbered debug bundles
#'
#' For code that catches errors itself (e.g. one failing section of a report
#' should not fail the target): each call of the returned function writes
#' `<target_name>_sectionNN.rds` / `.txt` bundles to `debug_dir`, numbered in
#' call order.
#'
#' @param debug_dir The debug directory; with `""` the sink does nothing.
#' @param target_name The target's name (an identifier).
#' @inheritParams capture_target_debug
#' @return A function of one condition, returning `NULL` invisibly.
#' @seealso [capture_target_debug()].
#' @examples
#' dir <- file.path(tempdir(), "data", "processed", "debug", "example")
#' sink <- create_debug_sink(dir, "report")
#' tryCatch(stop("section failed"), error = sink)
#' @export
create_debug_sink <- function(
  debug_dir,
  target_name,
  private_root = "data/processed"
) {
  force(debug_dir)
  force(target_name)
  force(private_root)
  n <- 0L
  function(condition) {
    if (!nzchar(debug_dir)) {
      return(invisible(NULL))
    }
    .require_private_path(debug_dir, private_root)
    dir.create(debug_dir, recursive = TRUE, showWarnings = FALSE)
    n <<- n + 1L
    .write_debug_bundle(
      debug_dir,
      sprintf("%s_section%02d", target_name, n),
      condition,
      NULL,
      character(0)
    )
    invisible(NULL)
  }
}

#' Read a target's status sidecar, re-checking every field
#'
#' @param debug_dir The debug directory.
#' @param target_name The target's name.
#' @return `NULL` when there is no sidecar (or `debug_dir` is `""`); otherwise a
#'   list with `target`, `status`, `class` (character), `code` (`NA` unless
#'   identifier-shaped), `counts` (named list of integers), `context` (`NA`
#'   unless pattern-safe) and `n_warnings` (integer, `NA` if unreadable). An
#'   unparseable sidecar gives `code = NA` and empty fields.
#' @seealso [capture_target_debug()].
#' @examples
#' read_debug_status(tempdir(), "no_such_target")
#' @export
read_debug_status <- function(debug_dir, target_name) {
  if (!nzchar(debug_dir)) {
    return(NULL)
  }
  path <- .debug_status_path(debug_dir, target_name)
  if (!file.exists(path)) {
    return(NULL)
  }
  .require_pkgs("jsonlite", "read_debug_status")
  s <- tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) list()
  )
  .sanitize_status(s)
}

.sanitize_status <- function(s) {
  if (!is.list(s)) {
    s <- list()
  }
  str_or_na <- function(x, pattern) {
    if (is.character(x) && length(x) == 1L && !is.na(x) && grepl(pattern, x)) {
      x
    } else {
      NA_character_
    }
  }
  cls <- as.character(unlist(s$class))
  nw <- suppressWarnings(as.integer(unlist(s$n_warnings)))
  list(
    target = str_or_na(s$target, .safe_name_pattern),
    status = str_or_na(s$status, .safe_name_pattern),
    class = cls[!is.na(cls) & grepl(.safe_name_pattern, cls)],
    code = str_or_na(s$code, .safe_name_pattern),
    counts = .safe_status_counts(s$counts),
    context = str_or_na(s$context, .safe_status_pattern),
    n_warnings = if (length(nw) == 1L) nw else NA_integer_
  )
}

# Runner helpers ----------------------------------------------------------------

.runner_abort <- function(message, class) {
  stop(structure(
    class = c(class, "dctools_runner_error", "error", "condition"),
    list(message = message, call = NULL)
  ))
}

.mask_count <- function(n, below = 5L) {
  ifelse(
    n >= 1 & n < below,
    paste0("<", below),
    as.character(as.integer(n))
  )
}

.parse_runner_args <- function(args) {
  if (!length(args)) {
    return(character(0))
  }
  if (!identical(args[1], "--names") || length(args) < 2L) {
    .runner_abort(
      "usage: run_pipeline_safe.R [--names <target> ...]",
      "dctools_runner_usage_error"
    )
  }
  nms <- args[-1]
  if (!all(grepl(.safe_name_pattern, nms))) {
    .runner_abort(
      "target names must be identifiers",
      "dctools_runner_usage_error"
    )
  }
  nms
}

.check_status_targets <- function(status_targets) {
  if (!length(status_targets)) {
    return(character(0))
  }
  if (is.null(names(status_targets))) {
    names(status_targets) <- status_targets
  }
  ok <- is.character(status_targets) &&
    all(grepl(.safe_name_pattern, status_targets)) &&
    all(grepl(.safe_name_pattern, names(status_targets)))
  if (!ok) {
    .runner_abort(
      "status_targets names and values must be identifiers",
      "dctools_runner_usage_error"
    )
  }
  status_targets
}

# One "  <target>: class=.. code=.. <count>=.. warnings: N" line per sidecar;
# every field is re-checked here, whatever wrote the file.
.format_status <- function(s, mask_below = 5L) {
  s <- .sanitize_status(s)
  counts <- unlist(s$counts)
  paste0(
    "  ",
    if (is.na(s$target)) "?" else s$target,
    ":",
    if (length(s$class)) paste0(" class=", s$class[1]) else "",
    if (is.na(s$code)) "" else paste0(" code=", s$code),
    if (length(counts)) {
      paste0(
        " ",
        paste0(
          names(counts),
          "=",
          .mask_count(counts, mask_below),
          collapse = " "
        )
      )
    } else {
      ""
    },
    " warnings: ",
    if (is.na(s$n_warnings)) "?" else .mask_count(s$n_warnings, mask_below)
  )
}

.format_run_summary <- function(
  progress,
  statuses,
  run_status_lines,
  debug_dir,
  mask_below = 5L
) {
  ok <- grepl(.safe_name_pattern, progress$name) &
    grepl(.safe_name_pattern, progress$progress)
  out <- c(
    "== targets ==",
    sprintf("%s: %s", progress$name[ok], progress$progress[ok])
  )
  if (length(statuses)) {
    out <- c(
      out,
      "== errors and warnings (detail in the debug directory) ==",
      vapply(statuses, .format_status, "", mask_below = mask_below)
    )
  }
  if (length(run_status_lines)) {
    out <- c(out, "== run status ==", run_status_lines)
  }
  c(out, paste0("debug directory: ", debug_dir))
}

.run_id_pattern <- "^[0-9]{8}-[0-9]{6}$"

.prune_debug_runs <- function(debug_root, keep = 20L) {
  runs <- sort(basename(list.dirs(debug_root, recursive = FALSE)))
  runs <- runs[grepl(.run_id_pattern, runs)]
  old <- utils::head(runs, max(0L, length(runs) - keep))
  for (r in old) {
    unlink(file.path(debug_root, r), recursive = TRUE)
  }
  invisible(old)
}

# "-- <label> --" then the target's lines, for each status target that finished
# (or was already up to date), in `status_targets` order.
.run_status_blocks <- function(
  progress,
  status_targets,
  read_target,
  format_status
) {
  done <- progress$name[
    progress$progress %in% c("completed", "built", "skipped")
  ]
  out <- character(0)
  for (label in names(status_targets)) {
    name <- status_targets[[label]]
    if (!name %in% done) {
      next
    }
    lines <- read_target(name)
    if (!is.null(format_status)) {
      lines <- format_status(lines)
    }
    if (!is.character(lines)) {
      .runner_abort(
        sprintf("status target %s did not give a character vector", name),
        "dctools_runner_status_error"
      )
    }
    out <- c(out, paste0("-- ", label, " --"), lines)
  }
  out
}

.read_status_file <- function(path) {
  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) list()
  )
}

.check_ledger_config <- function(ledger) {
  allowed <- c(
    "dir",
    "reportable",
    "links",
    "extra_inputs",
    "documents",
    "records"
  )
  if (
    !is.list(ledger) ||
      is.null(names(ledger)) ||
      !all(names(ledger) %in% allowed)
  ) {
    .runner_abort(
      paste0(
        "ledger must be a named list with elements from: ",
        paste(allowed, collapse = ", ")
      ),
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

# Exported: the runner -------------------------------------------------------------

#' Run a targets pipeline printing only disclosure-safe output
#'
#' Runs `targets::tar_make()` in the current directory with every byte the
#' pipeline writes (stdout, stderr, messages, warnings, error text) sent to a
#' per-run debug directory, `<debug_root>/<run_id>/`, and prints to stdout only
#' an allowlist:
#' * `== targets ==`: each target's progress (`completed`, `skipped`,
#'   `errored`, ...);
#' * `== errors and warnings ==`: one line per status sidecar written by
#'   [capture_target_debug()] this run: class, identifier-shaped code,
#'   identifier-named counts (values from 1 to `mask_below - 1` shown as
#'   `<mask_below`) and the warning count;
#' * `== run status ==`: the lines of each finished `status_targets` target;
#' * the debug directory's path.
#'
#' Detail goes to `runner.log` (the runner's own messages, warnings and errors)
#' and `tar_make.log` (the pipeline process's output) in the debug directory,
#' next to the bundles [capture_target_debug()] writes. Only the newest `keep`
#' run directories are kept.
#'
#' **Trust boundary.** Every field printed from the progress table and the
#' sidecars is re-checked against identifier/integer patterns. The
#' `== run status ==` lines are not: they are printed as given, so the status
#' targets (or `format_status`) are responsible for their disclosure safety.
#'
#' A project calls this from a small script, so it can be run as one command
#' and exit with the status:
#' ```
#' # code/pipeline/run_pipeline_safe.R
#' quit(status = dctools::run_targets_safe(
#'   commandArgs(trailingOnly = TRUE),
#'   status_targets = c(COHORT_A = "a_run_status")
#' ), save = "no")
#' ```
#' and is run as `Rscript code/pipeline/run_pipeline_safe.R [--names <target> ...]`
#' from the project root.
#'
#' @param args Command-line arguments: none (build everything) or
#'   `"--names"` followed by identifier-shaped target names.
#' @param status_targets A character vector of target names whose values are
#'   printed under `== run status ==`, labelled by the vector's names (the
#'   target names when unnamed). Names and values must be identifiers.
#' @param format_status `NULL`, in which case each status target's value must be
#'   a character vector, or a function turning a status target's value into a
#'   character vector of lines.
#' @param debug_root Where the per-run debug directories go. Must lie under
#'   `private_root`.
#' @param private_root A path segment (default `"data/processed"`) that the
#'   debug directories must lie under; see [capture_target_debug()].
#' @param keep How many run directories to keep under `debug_root`.
#' @param mask_below Counts from 1 to `mask_below - 1` print as
#'   `<mask_below`.
#' @param run_id This run's directory name, `YYYYMMDD-HHMMSS`; defaults to
#'   the current time.
#' @param ledger `NULL`, or a named list turning on the run ledger and audit
#'   (see [write_run_ledger()] and [audit_run()]): `dir` (default
#'   `"docs/runs"`), `reportable`, `links`, `extra_inputs`, `documents`,
#'   `records`. With a ledger, a working tree with uncommitted or untracked
#'   files outside `dir` is refused before the pipeline runs (runner failure
#'   `dctools_runner_dirty_tree_error`); after the run the ledger is written
#'   and audited, and stdout gains an `== audit ==` block with one line per
#'   check, the verdict and the ledger's path.
#' @return The exit status, invisibly: `0L` when every target succeeded (and,
#'   with a ledger, the audit passed), `1L` when a target errored, `2L` when
#'   the runner itself failed, `3L` when no target errored but the audit's
#'   verdict was not `PASS`. When several apply the order of precedence is
#'   `2L` (including a ledger or audit failure after the run), then `1L`,
#'   then `3L`. On a runner failure stdout gets only
#'   `runner failed: <condition class>`, with the detail in `runner.log` when
#'   the debug directory could be made.
#' @seealso [capture_target_debug()], [abort_safe()].
#' @examples
#' \dontrun{
#' # from a targets project's root
#' run_targets_safe(c("--names", "model_fit"))
#' }
#' @export
run_targets_safe <- function(
  args = character(0),
  status_targets = character(0),
  format_status = NULL,
  debug_root = "data/processed/debug",
  private_root = "data/processed",
  keep = 20L,
  mask_below = 5L,
  run_id = format(Sys.time(), "%Y%m%d-%H%M%S"),
  ledger = NULL
) {
  state <- new.env()
  tryCatch(
    .run_targets_safe(
      state,
      args,
      status_targets,
      format_status,
      debug_root,
      private_root,
      keep,
      mask_below,
      run_id,
      ledger
    ),
    error = function(e) {
      if (!is.null(state$log)) {
        try(
          cat(
            "runner failed: ",
            conditionMessage(e),
            "\ncall: ",
            paste(deparse(conditionCall(e)), collapse = " "),
            "\n",
            file = state$log,
            append = TRUE,
            sep = ""
          ),
          silent = TRUE
        )
      }
      cls <- class(e)[1]
      if (!grepl(.safe_name_pattern, cls)) {
        cls <- "error"
      }
      cat("runner failed: ", cls, "\n", sep = "")
      invisible(2L)
    }
  )
}

.run_targets_safe <- function(
  state,
  args,
  status_targets,
  format_status,
  debug_root,
  private_root,
  keep,
  mask_below,
  run_id,
  ledger
) {
  if (
    !is.character(run_id) ||
      length(run_id) != 1L ||
      !grepl(.run_id_pattern, run_id)
  ) {
    .runner_abort(
      "run_id must look like YYYYMMDD-HHMMSS",
      "dctools_runner_usage_error"
    )
  }
  .require_private_path(debug_root, private_root)
  debug_dir <- file.path(debug_root, run_id)
  dir.create(debug_dir, recursive = TRUE, showWarnings = FALSE)
  state$log <- file.path(debug_dir, "runner.log")
  log_line <- function(...) {
    cat(..., "\n", file = state$log, append = TRUE, sep = "")
  }
  .require_pkgs(c("targets", "tidyselect", "jsonlite"), "run_targets_safe")
  selected <- .parse_runner_args(args)
  status_targets <- .check_status_targets(status_targets)
  if (!is.null(format_status) && !is.function(format_status)) {
    .runner_abort(
      "format_status must be NULL or a function",
      "dctools_runner_usage_error"
    )
  }
  if (!is.null(ledger)) {
    ledger <- .check_ledger_config(ledger)
    dirty <- .git_dirty_files(".", .ledger_dir_in_repo(ledger$dir, "."))
    if (length(dirty)) {
      log_line(
        "uncommitted or untracked files: ",
        paste(dirty, collapse = ", ")
      )
      .runner_abort(
        "the working tree has uncommitted changes; commit them before a ledgered run",
        "dctools_runner_dirty_tree_error"
      )
    }
  }
  log_line(
    "run ",
    run_id,
    "; targets: ",
    if (length(selected)) paste(selected, collapse = " ") else "all"
  )
  old_env <- Sys.getenv(c("DCTOOLS_RUN_ID", "DCTOOLS_DEBUG_DIR"), unset = NA)
  on.exit(.restore_env(old_env), add = TRUE)
  Sys.setenv(
    DCTOOLS_RUN_ID = run_id,
    DCTOOLS_DEBUG_DIR = normalizePath(debug_dir)
  )

  withCallingHandlers(
    {
      tar_log <- file.path(debug_dir, "tar_make.log")
      # show = FALSE: targets defaults callr's `show` to TRUE, which copies
      # everything the pipeline process writes to this process's stdout too.
      callr_arguments <- list(stdout = tar_log, stderr = "2>&1", show = FALSE)
      made <- tryCatch(
        {
          # `names` is a tidyselect expression captured unevaluated, so each
          # call is written out rather than built.
          if (length(selected)) {
            targets::tar_make(
              names = tidyselect::any_of(selected),
              reporter = "silent",
              callr_arguments = callr_arguments
            )
          } else {
            targets::tar_make(
              reporter = "silent",
              callr_arguments = callr_arguments
            )
          }
          TRUE
        },
        error = function(e) {
          log_line("tar_make error: ", conditionMessage(e))
          FALSE
        }
      )
      progress <- as.data.frame(targets::tar_progress(fields = "progress"))
      status_files <- sort(list.files(
        debug_dir,
        pattern = "\\.status\\.json$",
        full.names = TRUE
      ))
      statuses <- lapply(status_files, .read_status_file)
      status_lines <- .run_status_blocks(
        progress,
        status_targets,
        targets::tar_read_raw,
        format_status
      )
      out <- .format_run_summary(
        progress,
        statuses,
        status_lines,
        debug_dir,
        mask_below
      )
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
          # the status before the audit: the audit's verdict is not part of it
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
    },
    warning = function(w) {
      log_line("warning: ", conditionMessage(w))
      invokeRestart("muffleWarning")
    },
    message = function(m) {
      log_line("message: ", conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
}

.restore_env <- function(old) {
  for (nm in names(old)) {
    if (is.na(old[[nm]])) {
      Sys.unsetenv(nm)
    } else {
      do.call(Sys.setenv, stats::setNames(list(old[[nm]]), nm))
    }
  }
}
