# Evidence export ------------------------------------------------------------------
#
# The run ledger is a private record. What may be committed is a filtered copy,
# built field by field (unknown fields are dropped, not passed through):
# strings must come from the committed source, as for the runner's output
# (output-schema.R), and digests are kept only for files whose bytes are
# themselves publishable or are raw inputs. A plain digest of a small private
# object, such as a store object holding a count, can be inverted by hashing
# its few candidate values, so store-object and dependency hashes stay private.

.export_schema_version <- 1L

# Every string constant in the project's R files, whole: declared paths
# ("data/raw/a.csv") are not identifier-shaped, so the word allowlist misses
# them.
.source_strings <- function(repo = ".") {
  files <- .project_r_files(repo)
  files <- files[file.exists(files)]
  unique(unlist(lapply(files, function(path) {
    exprs <- tryCatch(parse(path, keep.source = TRUE), error = function(e) NULL)
    pd <- if (is.null(exprs)) NULL else utils::getParseData(exprs)
    if (is.null(pd)) {
      return(character(0))
    }
    gsub("^[\"']|[\"']$", "", pd$text[pd$token == "STR_CONST"])
  })))
}

.tracked_files <- function(repo = ".") {
  tryCatch(.git(repo, "ls-files"), error = function(e) character(0))
}

.keep_if <- function(x, allowed) {
  x <- as.character(unlist(x))
  x[x %in% allowed]
}

# The filtered ledger. `allow` holds the identifier allowlist, `paths` the
# declared paths and tracked files, `documents_text` the declared documents
# (decision ids are checked against it).
.export_ledger <- function(ledger, allow, paths, documents_text) {
  withheld <- list(
    targets = 0L,
    paths = 0L,
    provenance = 0L,
    links = 0L,
    names = 0L
  )
  bump <- function(what, n = 1L) {
    withheld[[what]] <<- withheld[[what]] + as.integer(n)
  }
  names_in <- function(x) {
    x <- as.character(unlist(x))
    bump("names", sum(!x %in% allow))
    I(x[x %in% allow])
  }
  path_entry <- function(path, fields) {
    path <- .as_chr(path)
    if (!is.na(path) && !path %in% paths) {
      bump("paths")
      path <- NA_character_
    }
    c(list(path = path), fields)
  }
  code <- ledger$code
  env <- ledger$environment
  targets <- Filter(Negate(is.null), lapply(ledger$targets, function(t) {
    name <- .as_chr(t$name)
    if (!name %in% allow) {
      bump("targets")
      return(NULL)
    }
    list(
      name = name,
      type = .as_chr(t$type),
      format = .as_chr(t$format),
      command = .as_chr(t$command),
      status = .as_chr(t$status),
      built = t$built,
      origin_run_id = .as_chr(t$origin_run_id),
      upstream = names_in(t$upstream),
      functions = lapply(t$functions, function(f) {
        list(
          name = if (.as_chr(f$name) %in% allow) .as_chr(f$name) else NA_character_,
          file = if (.as_chr(f$file) %in% paths) .as_chr(f$file) else NA_character_,
          line_start = .int_or_na(f$line_start),
          line_end = .int_or_na(f$line_end)
        )
      })
    )
  }))
  provenance_entry <- function(p) {
    ok <- all(c(.as_chr(p$report), .as_chr(p$id), .as_chr(p$target)) %in% allow) &&
      (is.na(.as_chr(p$file)) || .as_chr(p$file) %in% paths)
    if (!ok) {
      bump("provenance")
      return(NULL)
    }
    fn <- .as_chr(p$function_name)
    list(
      report = .as_chr(p$report),
      id = .as_chr(p$id),
      file = .as_chr(p$file),
      line_start = .int_or_na(p$line_start),
      line_end = .int_or_na(p$line_end),
      code = .as_chr(p$code),
      function_name = if (is.na(fn) || fn %in% allow || startsWith(fn, "(")) fn else NA_character_,
      function_file = if (.as_chr(p$function_file) %in% paths) .as_chr(p$function_file) else NA_character_,
      function_line_start = .int_or_na(p$function_line_start),
      function_line_end = .int_or_na(p$function_line_end),
      target = .as_chr(p$target)
    )
  }
  links <- Filter(Negate(is.null), lapply(ledger$links, function(l) {
    id <- .as_chr(l$decision_id)
    target <- .as_chr(l$target)
    if (
      is.na(id) || !grepl(id, documents_text, fixed = TRUE) ||
        (!is.na(target) && !target %in% allow)
    ) {
      bump("links")
      return(NULL)
    }
    list(
      decision_id = id,
      decision_status = if (grepl(.safe_name_pattern, .as_chr(l$decision_status))) {
        .as_chr(l$decision_status)
      } else {
        NA_character_
      },
      target = target,
      role = if (.as_chr(l$role) %in% c("args", "evidence")) .as_chr(l$role) else NA_character_
    )
  }))
  out <- list(
    export = list(
      schema_version = .export_schema_version,
      ledger_schema_version = .int_or_na(ledger$schema_version)
    ),
    run = list(
      run_id = .as_chr(ledger$run$run_id),
      output_schema_version = .int_or_na(ledger$run$output_schema_version),
      written = .as_chr(ledger$run$written),
      requested = names_in(ledger$run$requested),
      exit_code = .int_or_na(ledger$run$exit_code)
    ),
    code = list(
      sha = .as_chr(code$sha),
      remote = .strip_credentials(.as_chr(code$remote)),
      clean = isTRUE(code$clean),
      n_dirty_files = length(unlist(code$dirty_files)),
      r_version = .as_chr(code$r_version),
      renv_lock_sha256 = .as_chr(code$renv_lock_sha256),
      dctools_version = .as_chr(code$dctools_version),
      dctools_remote_sha = .as_chr(code$dctools_remote_sha)
    ),
    environment = if (is.list(env)) {
      comp <- env$computational
      list(
        computational = list(
          r_version = .as_chr(comp$r_version),
          blas = .as_chr(comp$blas),
          lapack = .as_chr(comp$lapack),
          lapack_version = .as_chr(comp$lapack_version),
          rng_kind = I(as.character(unlist(comp$rng_kind))),
          collate = .as_chr(comp$collate),
          threads = lapply(comp$threads, .as_chr),
          mc_cores = .as_chr(comp$mc_cores),
          packages = lapply(comp$packages, function(p) {
            list(
              package = .as_chr(p$package),
              version = .as_chr(p$version),
              remote_sha = .as_chr(p$remote_sha)
            )
          })
        ),
        full = if (is.list(env$full)) {
          os <- env$full$os
          list(
            platform = .as_chr(env$full$platform),
            os = list(
              sysname = .as_chr(os$sysname),
              release = .as_chr(os$release),
              version = .as_chr(os$version),
              machine = .as_chr(os$machine)
            ),
            locale = .as_chr(env$full$locale),
            time_zone = .as_chr(env$full$time_zone),
            installed = lapply(env$full$installed, function(p) {
              list(
                package = .as_chr(p$package),
                version = .as_chr(p$version),
                remote_sha = .as_chr(p$remote_sha)
              )
            })
          )
        }
      )
    },
    inputs = lapply(ledger$inputs, function(i) {
      path_entry(i$path, list(sha256 = .as_chr(i$sha256)))
    }),
    input_stability = if (is.list(ledger$input_stability)) {
      lapply(ledger$input_stability, function(e) {
        path_entry(e$path, list(
          declared = isTRUE(e$declared),
          undeclared_index = .int_or_na(e$undeclared_index),
          sha256_before = .as_chr(e$sha256_before),
          sha256_after = .as_chr(e$sha256_after)
        ))
      })
    },
    documents = lapply(ledger$documents, function(d) {
      path_entry(d$path, list(sha256 = .as_chr(d$sha256)))
    }),
    targets = targets,
    outdated = names_in(ledger$outdated),
    links = links,
    reportable = Filter(Negate(is.null), lapply(ledger$reportable, function(r) {
      if (!.as_chr(r$name) %in% allow) {
        bump("targets")
        return(NULL)
      }
      list(name = .as_chr(r$name), available = isTRUE(r$available))
    })),
    records = lapply(ledger$records, function(r) {
      path_entry(r$path, list(
        sha256 = .as_chr(r$sha256),
        stamps = lapply(r$stamps, function(s) {
          list(
            run_id = .as_chr(s$run_id),
            sha = .as_chr(s$sha),
            dctools_version = .as_chr(s$dctools_version),
            objects = names_in(names(s$objects))
          )
        })
      ))
    }),
    provenance = Filter(Negate(is.null), lapply(ledger$provenance, provenance_entry)),
    unprovenanced = Filter(Negate(is.null), lapply(ledger$unprovenanced, provenance_entry))
  )
  out$export$withheld <- withheld
  out
}

#' Export a run's evidence for committing
#'
#' Writes a filtered copy of a run's ledger and audit pages to `out_dir`:
#' `ledger.json`, `audit.md` and `provenance.md`. The ledger written by
#' [write_run_ledger()] is a private record; this is what may be committed.
#'
#' The copy is built field by field, so a field this function does not know
#' is dropped rather than passed through. Strings must come from the
#' committed source, as for [run_targets_safe()]'s output: a target, report,
#' count id or function name outside the allowlist (target names from
#' `tar_manifest()`, symbols and identifier-shaped words of string constants
#' in the project's R files) is dropped, which removes dynamic branches; a
#' path that is neither a string constant in the source nor a tracked file
#' is replaced by `null`; a decision id must appear in a declared document.
#' Digests are kept only for files: inputs, documents and rendered records.
#' Store-object digests, targets' data and dependency hashes, the objects a
#' record stamp names (by digest), library paths and dirty file names stay
#' private: a plain digest of a small object can be inverted by hashing its
#' candidate values. `export$withheld` counts what was dropped. The audit
#' page keeps each check's status and counts but not its details.
#'
#' Run it from the project root, after the run and its audit, against the
#' store that run produced.
#'
#' @param ledger_path Path to the run's `<run_id>.json`.
#' @param out_dir Directory to write to, such as
#'   `"evidence/runs/<run_id>"`.
#' @param result The run's [audit_run()] result; `NULL` reruns the audit.
#' @param store,script The targets store and script; default to the
#'   project's configuration.
#' @param repo The git repository.
#' @return `out_dir`, invisibly, with the `withheld` counts as an attribute.
#' @seealso [write_run_ledger()], [audit_run()].
#' @examples
#' \dontrun{
#' export_run_evidence("docs/runs/20261020-093000.json",
#'                     "evidence/runs/20261020-093000")
#' }
#' @export
export_run_evidence <- function(
  ledger_path,
  out_dir,
  result = NULL,
  store = NULL,
  script = NULL,
  repo = "."
) {
  .require_pkgs(c("targets", "jsonlite", "digest"), "export_run_evidence")
  if (is.null(store)) {
    store <- targets::tar_config_get("store")
  }
  if (is.null(script)) {
    script <- targets::tar_config_get("script")
  }
  ledger <- jsonlite::read_json(ledger_path, simplifyVector = FALSE)
  if (is.null(result)) {
    result <- audit_run(ledger_path, store = store, script = script, repo = repo)
  }
  manifest <- .read_manifest(script)
  allow <- .output_allowlist(manifest$name, repo)
  literal <- unlist(lapply(manifest$command, .literal_paths))
  paths <- unique(c(.source_strings(repo), literal, .tracked_files(repo)))
  documents <- vapply(ledger$documents, function(d) .as_chr(d$path), "")
  documents <- documents[!is.na(documents) & file.exists(documents)]
  documents_text <- paste(
    unlist(lapply(documents, readLines, warn = FALSE)),
    collapse = "\n"
  )
  exported <- .export_ledger(ledger, allow, paths, documents_text)
  reports <- .load_reportable(
    store,
    vapply(exported$reportable, function(r) r$name, "")
  )
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(
    exported,
    file.path(out_dir, "ledger.json"),
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null",
    na = "null",
    digits = NA
  )
  public_result <- result
  public_result$detail <- lapply(seq_len(nrow(result)), function(i) character(0))
  writeLines(
    c(
      .render_audit_md(exported, public_result),
      "",
      "Check details stay in the private audit page next to the run's ledger."
    ),
    file.path(out_dir, "audit.md")
  )
  writeLines(
    .render_provenance_md(exported, reports),
    file.path(out_dir, "provenance.md")
  )
  invisible(structure(out_dir, withheld = exported$export$withheld))
}
