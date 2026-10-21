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
    if (nrow(failed)) paste0(failed$item, ": ", failed$detail) else character(0)
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
    return(.item(
      label,
      FALSE,
      sprintf("%s is not tracked at the run's commit", file)
    ))
  }
  from <- .int_or_na(p$line_start)
  to <- .int_or_na(p$line_end)
  if (
    is.na(from) || is.na(to) || from < 1L || to > length(lines) || from > to
  ) {
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
  full_sha <- !is.na(sha) && grepl("^[0-9a-f]{40}$", sha)
  has_commit <- full_sha &&
    .git_ok(repo, c("cat-file", "-e", paste0(sha, "^{commit}")))
  items <- list(
    .item(
      "commit",
      has_commit,
      if (full_sha) {
        "the run's commit is not in this repository"
      } else {
        "the ledger's sha is not a full commit SHA"
      }
    ),
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
    if (is.na(nm)) {
      return(.item("target", FALSE, "a ledger target has no name"))
    }
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
    .item(
      nm,
      all(same),
      paste("differs:", paste(names(same)[!same], collapse = ", "))
    )
  })
  extra <- setdiff(meta$name, in_ledger)
  items <- c(
    items,
    lapply(extra, function(nm) {
      .item(nm, FALSE, "in the store but not in the ledger")
    })
  )
  .check_result("C2", .bind_items(items), "no targets in the ledger")
}

# C3 Fresh ----------------------------------------------------------------------

.check_fresh <- function(ledger, script, store) {
  has_recorded <- is.list(ledger$outdated)
  recorded <- unlist(ledger$outdated)
  now <- targets::tar_outdated(
    script = script,
    store = store,
    reporter = "silent"
  )
  .check_result(
    "C3",
    .bind_items(list(
      .item(
        "at run time",
        has_recorded && !length(recorded),
        if (has_recorded) {
          paste("outdated:", paste(recorded, collapse = ", "))
        } else {
          "the ledger does not record outdated targets"
        }
      ),
      .item(
        "now",
        !length(now),
        paste("outdated:", paste(now, collapse = ", "))
      )
    )),
    ""
  )
}

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
    .item(
      path,
      identical(now, .as_chr(f$sha256)),
      "SHA-256 differs from the ledger"
    )
  })
  .check_result(
    "C5",
    .bind_items(items),
    "no inputs or documents in the ledger"
  )
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
    bad <- vapply(
      targets,
      function(t) {
        if (is.na(t)) {
          return("no target")
        }
        if (!t %in% names(status)) {
          return(paste(t, "is not in the run"))
        }
        if (!status[[t]] %in% c("completed", "skipped", "built")) {
          return(paste0(
            t,
            " was not built in this run (status ",
            if (is.na(status[[t]])) "none" else status[[t]],
            ")"
          ))
        }
        ""
      },
      ""
    )
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
      return(.item(
        path,
        FALSE,
        sprintf("%d stamps (expected 1)", length(stamps))
      ))
    }
    s <- stamps[[1]]
    run_id <- .as_chr(s$run_id)
    sha <- .as_chr(s$sha)
    problems <- c(
      if (is.na(run_id)) {
        "the stamp has no run id"
      } else if (!identical(run_id, .as_chr(ledger$run$run_id))) {
        "stamped with another run"
      },
      if (is.na(sha)) {
        "the stamp has no commit"
      } else if (!identical(sha, .as_chr(ledger$code$sha))) {
        "stamped with another commit"
      },
      if (!length(s$objects)) {
        "the stamp names no objects"
      },
      unlist(lapply(names(s$objects), function(nm) {
        recorded <- .as_chr(s$objects[[nm]])
        if (!nm %in% names(objects)) {
          paste(nm, "is not in the ledger")
        } else {
          in_store <- .sha256_file(.object_path(store, nm))
          if (is.na(recorded) || is.na(objects[[nm]]) || is.na(in_store)) {
            paste(nm, "has no hash")
          } else if (
            !identical(recorded, objects[[nm]]) ||
              !identical(recorded, in_store)
          ) {
            paste(nm, "differs from what the record read")
          }
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
      (identical(absolute, relative) ||
        endsWith(absolute, paste0("/", relative))))
}

.same_provenance <- function(report_p, ledger_p) {
  if (is.null(ledger_p)) {
    return(FALSE)
  }
  fields <- c(
    "line_start",
    "line_end",
    "code",
    "function_name",
    "function_line_start",
    "function_line_end",
    "target"
  )
  all(vapply(
    fields,
    function(f) {
      identical(.as_chr(report_p[[f]]), .as_chr(ledger_p[[f]]))
    },
    logical(1)
  )) &&
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
          identical(
            .as_chr(ledger$code$dctools_version),
            .as_chr(engine$version)
          ),
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
}
