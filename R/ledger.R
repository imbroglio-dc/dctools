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
    full <- file.path(repo, f)
    # A tracked file deleted from the working tree is reported by code$clean.
    lines <- if (file.exists(full)) {
      tryCatch(readLines(full, warn = FALSE), error = function(e) NULL)
    }
    if (is.null(lines)) .empty_spans() else .spans_in_lines(lines, f)
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
      list(
        path = p,
        sha256 = .sha256_file(p),
        targets_hash = .as_chr(files$data[[i]])
      )
    })
  }))
  extra <- lapply(extra_inputs, function(p) {
    list(path = p, sha256 = .sha256_file(p), targets_hash = NA_character_)
  })
  c(from_targets, extra)
}

# Only the stamp's four known fields; objects holds SHA-256 strings only.
.whitelist_stamp <- function(stamp) {
  objects <- stamp$objects
  if (!is.list(objects)) {
    objects <- list()
  }
  objects <- objects[vapply(
    objects,
    function(o) {
      is.character(o) && length(o) == 1L && grepl("^[0-9a-f]{64}$", o)
    },
    logical(1)
  )]
  list(
    run_id = .as_chr(stamp$run_id),
    sha = .as_chr(stamp$sha),
    dctools_version = .as_chr(stamp$dctools_version),
    objects = objects
  )
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
    lapply(stats::setNames(need, need), function(col) {
      .as_chr(links[[col]][[i]])
    })
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
      list(
        path = p,
        sha256 = .sha256_file(p),
        stamps = lapply(.parse_stamps(p), .whitelist_stamp)
      )
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
