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

# Every function expression in a file's lines, at any nesting level: its line
# span, the column of its start, and the name it is assigned to (`name <-
# function`, `name = function`), or NA for an anonymous function (an argument
# of lapply(), say). A closure's srcref spans exactly its function
# expression, so this is what a recorded function span is checked against.
.function_defs <- function(lines) {
  empty <- data.frame(
    name = character(0),
    line_start = integer(0),
    col_start = integer(0),
    line_end = integer(0),
    stringsAsFactors = FALSE
  )
  exprs <- tryCatch(
    parse(text = lines, keep.source = TRUE),
    error = function(e) NULL
  )
  pd <- if (is.null(exprs)) NULL else utils::getParseData(exprs)
  if (is.null(pd) || !nrow(pd)) {
    return(empty)
  }
  keyword <- pd[pd$token %in% c("FUNCTION", "'\\\\'"), , drop = FALSE]
  if (!nrow(keyword)) {
    return(empty)
  }
  fn <- pd[match(keyword$parent, pd$id), , drop = FALSE]
  name <- vapply(
    seq_len(nrow(fn)),
    function(i) {
      kids <- pd[pd$parent == fn$parent[[i]], , drop = FALSE]
      kids <- kids[order(kids$line1, kids$col1), , drop = FALSE]
      if (
        nrow(kids) != 3L ||
          !kids$token[[2]] %in% c("LEFT_ASSIGN", "EQ_ASSIGN") ||
          kids$id[[3]] != fn$id[[i]]
      ) {
        return(NA_character_)
      }
      target <- pd[pd$parent == kids$id[[1]], , drop = FALSE]
      if (nrow(target) == 1L && target$token[[1]] == "SYMBOL") {
        gsub("^`|`$", "", target$text[[1]])
      } else {
        NA_character_
      }
    },
    ""
  )
  out <- data.frame(
    name = name,
    line_start = as.integer(fn$line1),
    col_start = as.integer(fn$col1),
    line_end = as.integer(fn$line2),
    stringsAsFactors = FALSE
  )
  out[order(out$line_start, out$col_start), , drop = FALSE]
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

.code_block <- function(repo, ledger_dir, records = character(0)) {
  root <- .git_root(repo)
  exclude <- .ledger_dir_in_repo(ledger_dir, repo)
  dirty <- .git_dirty_files(repo, exclude, .records_in_repo(records, repo))
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

# Input stability -----------------------------------------------------------------
#
# Inputs are hashed before the pipeline runs and again when the ledger is
# written. Endpoint hashing detects a change between the two, not a change and
# change back in between. Files found under an input directory that the
# pipeline does not declare are recorded by number, not name: an undeclared
# file's name has not been through the publish test.

# The paths in a file target's command when it is a literal: "a.csv" or
# c("a.csv", "b.csv"). Anything computed is known only after the run.
.literal_paths <- function(command) {
  expr <- tryCatch(parse(text = command)[[1]], error = function(e) NULL)
  if (is.character(expr)) {
    return(expr)
  }
  if (is.call(expr) && identical(expr[[1]], as.name("c"))) {
    parts <- as.list(expr)[-1]
    if (length(parts) && all(vapply(parts, is.character, logical(1)))) {
      return(unlist(parts))
    }
  }
  character(0)
}

# README files in private zones are notes about the data, not data.
.files_under <- function(dirs) {
  files <- as.character(unlist(lapply(sub("/+$", "", dirs), function(d) {
    list.files(d, recursive = TRUE, full.names = TRUE)
  })))
  sort(unique(files[!grepl("^README", basename(files))]))
}

.hash_paths <- function(paths) {
  lapply(paths, function(p) list(path = p, sha256 = .sha256_file(p)))
}

# Run before tar_make(): the declared inputs, the literal paths of file
# targets, and everything under the input directories.
.read_manifest <- function(script, callr_arguments = list(show = FALSE)) {
  as.data.frame(targets::tar_manifest(
    fields = c("name", "command", "format"),
    script = script,
    callr_arguments = callr_arguments
  ))
}

.inputs_before <- function(
  script,
  extra_inputs = character(0),
  documents = character(0),
  input_dirs = character(0),
  callr_arguments = list(show = FALSE),
  manifest = .read_manifest(script, callr_arguments)
) {
  files <- manifest[!is.na(manifest$format) & manifest$format == "file", ]
  literal <- unlist(lapply(files$command, .literal_paths))
  paths <- unique(c(extra_inputs, documents, literal, .files_under(input_dirs)))
  .hash_paths(paths)
}

# File targets with no upstream target: inputs, not outputs.
.input_file_paths <- function(meta, network) {
  vertices <- network$vertices
  target_names <- vertices$name[vertices$type %in% c("stem", "pattern")]
  files <- meta[!is.na(meta$format) & meta$format == "file", , drop = FALSE]
  is_input <- vapply(
    files$name,
    function(nm) !any(network$edges$from[network$edges$to == nm] %in% target_names),
    logical(1)
  )
  unique(unlist(files$path[is_input]))
}

.stability_block <- function(before, declared) {
  if (is.null(before)) {
    return(NULL)
  }
  before_paths <- vapply(before, function(b) .as_chr(b$path), "")
  paths <- unique(c(before_paths, declared))
  undeclared <- 0L
  lapply(paths, function(p) {
    hit <- before[before_paths == p]
    entry <- list(
      path = p,
      declared = p %in% declared,
      undeclared_index = NA_integer_,
      sha256_before = if (length(hit)) .as_chr(hit[[1]]$sha256) else NA_character_,
      sha256_after = .sha256_file(p)
    )
    if (!entry$declared) {
      undeclared <<- undeclared + 1L
      entry$path <- NA_character_
      entry$undeclared_index <- undeclared
    }
    entry
  })
}

# Origins --------------------------------------------------------------------------
#
# A target the run skipped was reused from an earlier build. Its origin is the
# newest earlier ledger in the same directory that built it with the same
# command, dependencies and data, or that already names its origin; otherwise
# it is unknown.

.prior_ledgers <- function(path, run_id) {
  files <- list.files(path, pattern = "^[0-9]{8}-[0-9]{6}\\.json$")
  ids <- sort(sub("\\.json$", "", files), decreasing = TRUE)
  ids <- ids[ids < run_id]
  lapply(ids, function(id) {
    tryCatch(
      jsonlite::read_json(file.path(path, paste0(id, ".json"))),
      error = function(e) NULL
    )
  })
}

.origin_of <- function(target, priors) {
  same <- function(a, b) identical(.as_chr(a), .as_chr(b))
  for (prior in priors) {
    for (t in prior$targets) {
      if (
        !same(t$name, target$name) ||
          !same(t$data, target$data) ||
          !same(t$command, target$command) ||
          !same(t$depend, target$depend)
      ) {
        next
      }
      if (!.is_missing(t$origin_run_id)) {
        return(.as_chr(t$origin_run_id))
      }
      if (same(t$status, "completed")) {
        return(.as_chr(prior$run$run_id))
      }
    }
  }
  NA_character_
}

.add_origins <- function(targets_block, run_id, priors) {
  lapply(targets_block, function(t) {
    built <- identical(t$status, "completed")
    t$built <- built
    t$origin_run_id <- if (built) {
      run_id
    } else if (identical(t$status, "skipped")) {
      .origin_of(t, priors)
    } else {
      NA_character_
    }
    t
  })
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
#' The clean-tree check ignores the ledger directory and the declared
#' `records` (a run rewrites them; check C7 vouches for records). Anything
#' else the run writes, notably the targets store and debug output, must be
#' git-ignored, or the tree is recorded as not clean and C1 fails.
#'
#' Schema version 2 adds:
#' * `environment`: both tiers of [capture_environment()];
#' * `input_stability`: each input's SHA-256 before the run (`inputs_before`,
#'   which [run_targets_safe()] supplies) and when the ledger is written. A
#'   file under `input_dirs` that is neither an input file target nor in
#'   `extra_inputs` or `documents` is recorded as undeclared, by number and
#'   without its name;
#' * per target, `built` and `origin_run_id`: the run that built a reused
#'   (skipped) target, found in the earlier ledgers in `path`, or `null`
#'   when unknown.
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
#' @param inputs_before `NULL`, or the inputs hashed before the run: a list of
#'   `list(path =, sha256 =)`. Without it, input stability is not recorded
#'   and check C10 is not evaluated.
#' @param input_dirs Directories holding the pipeline's input data (e.g.
#'   `"data/raw"`), inventoried for undeclared files.
#' @param env_packages Packages for the computational tier of
#'   [capture_environment()].
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
  exit_code = NA_integer_,
  inputs_before = NULL,
  input_dirs = character(0),
  env_packages = character(0)
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
  declared <- unique(c(
    .input_file_paths(meta, network),
    extra_inputs,
    documents
  ))
  if (length(input_dirs) && !is.null(inputs_before)) {
    seen <- vapply(inputs_before, function(b) .as_chr(b$path), "")
    late <- setdiff(.files_under(input_dirs), seen)
    inputs_before <- c(inputs_before, lapply(late, function(p) {
      list(path = p, sha256 = NA_character_)
    }))
  }
  targets_block <- .add_origins(
    .targets_block(
      meta,
      .read_progress(store),
      network,
      .function_spans(repo),
      store
    ),
    run_id,
    .prior_ledgers(path, run_id)
  )
  ledger <- list(
    schema_version = 2L,
    run = list(
      run_id = run_id,
      output_schema_version = .output_schema_version,
      written = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
      requested = I(requested),
      exit_code = as.integer(exit_code)
    ),
    code = .code_block(repo, path, records),
    environment = capture_environment(env_packages),
    inputs = .input_block(meta, extra_inputs),
    input_stability = .stability_block(inputs_before, declared),
    documents = lapply(documents, function(p) {
      list(path = p, sha256 = .sha256_file(p))
    }),
    targets = targets_block,
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

# trust probe (not for merge): a change to a frozen verifier file.
