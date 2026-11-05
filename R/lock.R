# Computation lock --------------------------------------------------------------
#
# A bounded, deterministic record of the settings each decision-linked target
# passes: the top-level call of its command and each argument, classified as a
# literal, a config value, a reference or unresolved. Project code is parsed,
# never run. Spec: biostat-support
# docs/superpowers/specs/2026-11-05-computation-lock-design.md.

.lock_schema_version <- 1L

.deparse1 <- function(expr) {
  paste(trimws(deparse(expr, width.cutoff = 500L)), collapse = " ")
}

.is_scalar_constant <- function(expr) {
  is.null(expr) ||
    (is.atomic(expr) && length(expr) == 1L &&
      ((is.numeric(expr) && (is.na(expr) || is.finite(expr))) || is.character(expr) || is.logical(expr)))
}

# The value of a literal expression, or a "not literal" sentinel.
.literal_value <- function(expr) {
  not_literal <- structure(list(), class = "dctools_not_literal")
  if (.is_scalar_constant(expr)) {
    return(expr)
  }
  if (is.call(expr) && identical(expr[[1]], as.name("-")) && length(expr) == 2L &&
    is.numeric(expr[[2]]) && length(expr[[2]]) == 1L && is.finite(expr[[2]])) {
    return(-expr[[2]])
  }
  if (is.call(expr) && identical(expr[[1]], as.name("c"))) {
    parts <- as.list(expr)[-1]
    if (!all(vapply(parts, .is_scalar_constant, logical(1))) ||
      any(vapply(parts, is.null, logical(1)))) {
      return(not_literal)
    }
    value <- unlist(parts)
    if (!is.null(names(parts)) && any(nzchar(names(parts)))) {
      return(as.list(stats::setNames(value, names(parts))))
    }
    return(value)
  }
  not_literal
}

# Keys of `config$a$b` / `config[["a"]][["b"]]`, or NULL for anything else.
.config_keys <- function(expr, symbol = "config") {
  keys <- character(0)
  while (is.call(expr)) {
    head <- expr[[1]]
    if (identical(head, as.name("$")) && length(expr) == 3L &&
      (is.name(expr[[3]]) || is.character(expr[[3]]))) {
      keys <- c(as.character(expr[[3]]), keys)
    } else if (identical(head, as.name("[[")) && length(expr) == 3L &&
      is.character(expr[[3]]) && length(expr[[3]]) == 1L) {
      keys <- c(expr[[3]], keys)
    } else {
      return(NULL)
    }
    expr <- expr[[2]]
  }
  if (identical(expr, as.name(symbol)) && length(keys)) keys else NULL
}

.config_lookup <- function(config_data, keys) {
  node <- config_data
  for (k in keys) {
    if (!is.list(node) || is.null(names(node)) || !k %in% names(node)) {
      return(structure(list(), class = "dctools_not_found"))
    }
    node <- node[[k]]
  }
  node
}

.lock_argument <- function(expr, name, position, config_data, config_declared) {
  arg <- list(
    position = position,
    name = if (is.null(name) || !nzchar(name)) NULL else name,
    expression = .deparse1(expr)
  )
  value <- .literal_value(expr)
  if (!inherits(value, "dctools_not_literal")) {
    return(c(arg, list(status = "literal", value = value)))
  }
  keys <- .config_keys(expr)
  if (!is.null(keys)) {
    key <- paste(keys, collapse = ".")
    if (!config_declared) {
      return(c(arg, list(status = "unresolved", reason = "no config file declared", config_key = key)))
    }
    found <- .config_lookup(config_data, keys)
    if (inherits(found, "dctools_not_found")) {
      return(c(arg, list(status = "unresolved", reason = "config key not found", config_key = key)))
    }
    return(c(arg, list(status = "config", config_key = key, value = found)))
  }
  if (is.name(expr)) {
    return(c(arg, list(status = "reference")))
  }
  c(arg, list(status = "unresolved", reason = "expression"))
}

# The function a top-level call names (`fn` or `pkg::fn`), or NULL when the
# command is not a call to a function by name (an operator, `{`, `if`, a lambda).
.lock_call_name <- function(expr) {
  if (!is.call(expr)) {
    return(NULL)
  }
  head <- expr[[1]]
  if (is.name(head)) {
    nm <- as.character(head)
    return(if (identical(make.names(nm), nm)) nm else NULL)
  }
  if (is.call(head) && length(head) == 3L &&
    (identical(head[[1]], as.name("::")) || identical(head[[1]], as.name(":::")))) {
    return(paste0(as.character(head[[2]]), as.character(head[[1]]), as.character(head[[3]])))
  }
  NULL
}

.lock_call <- function(command, config_data, config_declared) {
  expr <- tryCatch(parse(text = command, keep.source = FALSE), error = function(e) NULL)
  if (length(expr) != 1L) {
    return(list(call = NULL, call_status = "unsupported", expression = command, arguments = list()))
  }
  expr <- expr[[1]]
  fn <- .lock_call_name(expr)
  if (is.null(fn)) {
    return(list(call = NULL, call_status = "unsupported", expression = .deparse1(expr), arguments = list()))
  }
  args <- as.list(expr)[-1]
  nms <- names(args)
  if (is.null(nms)) {
    nms <- rep("", length(args))
  }
  arguments <- lapply(seq_along(args), function(i) {
    if (identical(args[[i]], quote(expr = ))) {
      name <- if (nzchar(nms[[i]])) nms[[i]] else NULL
      return(list(position = i, name = name, expression = "", status = "unresolved", reason = "empty argument"))
    }
    .lock_argument(args[[i]], nms[[i]], i, config_data, config_declared)
  })
  list(call = fn, call_status = "supported", expression = NULL, arguments = arguments)
}

# file:line of each `tar_target(<name>, ...)` in the committed R files, from
# parse data (the files are parsed, never run). The first definition wins.
.target_locations <- function(repo = ".") {
  files <- sort(.project_r_files(repo))
  out <- list()
  for (path in files) {
    exprs <- tryCatch(
      parse(path, keep.source = TRUE),
      error = function(e) NULL,
      warning = function(w) NULL
    )
    pd <- if (is.null(exprs)) NULL else utils::getParseData(exprs)
    if (is.null(pd) || !nrow(pd)) {
      next
    }
    pd <- pd[pd$terminal, , drop = FALSE]
    pd <- pd[order(pd$line1, pd$col1), , drop = FALSE]
    calls <- which(pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == "tar_target")
    for (i in calls) {
      j <- i + 1L
      if (j > nrow(pd) || pd$token[j] != "'('") {
        next
      }
      j <- j + 1L
      if (j + 1L <= nrow(pd) && pd$token[j] == "SYMBOL_SUB" && pd$text[j] == "name" &&
        pd$token[j + 1L] == "EQ_SUB") {
        j <- j + 2L
      }
      if (j > nrow(pd) || !pd$token[j] %in% c("SYMBOL", "STR_CONST")) {
        next
      }
      nm <- gsub("^[\"'`]|[\"'`]$", "", pd$text[j])
      if (is.null(out[[nm]])) {
        out[[nm]] <- list(file = .repo_relative(path, repo), line = pd$line1[i])
      }
    }
  }
  out
}

.read_lock_config <- function(config, repo) {
  if (is.null(config)) {
    return(NULL)
  }
  .require_pkgs("yaml", "computation_lock")
  yaml::read_yaml(file.path(repo, config))
}

#' Build, write, check and review a computation lock
#'
#' The computation lock (architecture section 7.2) records, for each
#' decision-linked target, the settings its command actually passes: the
#' top-level call and each argument, classified by what can be resolved
#' without running project code.
#'
#' * `literal`: a number, string, `TRUE`/`FALSE`, `NULL`, `NA`, a negative
#'   number, or `c()` of these; the value is recorded.
#' * `config`: `config$a$b` or `config[["a"]][["b"]]` found in the declared
#'   YAML `config` file; the key and value are recorded.
#' * `reference`: a bare symbol (another target, a global, a function).
#' * `unresolved`: anything else, or a config key that is missing or has no
#'   config file, with a `reason`. Unresolved items stay visible until a
#'   human reviews them; nothing is guessed.
#'
#' A command that is not a call to a function by name (an operator, a `{`
#' block, `if`, a lambda) is `call_status: unsupported`, a target missing
#' from the manifest is `missing_target`, and a decision with no target is
#' listed with `target: null`. Helpers are not followed. Commands come from
#' `tar_manifest()`; locations come from parsing the committed R files for
#' `tar_target(<name>, ...)` (`location: null` for targets defined another
#' way). The lock (schema version 1) is JSON with entries sorted by decision
#' and target and no timestamp, commit or generator version, so the same
#' source always gives the same bytes.
#'
#' `check_computation_lock()` rebuilds the lock and compares it byte for byte
#' with the committed file; CI runs it so a hand-edited or stale lock fails.
#' `lock_review_table()` renders the review table, with a change column
#' against a `baseline` lock (the last approved one, e.g.
#' `read_computation_lock(ref = "plan-v1")`). The lock acknowledges stated
#' coverage; static extraction is not proof of runtime behavior.
#'
#' @param links A data frame with character columns `decision_id`,
#'   `decision_status`, `target` and `role`, as for [write_run_ledger()].
#' @param config `NULL`, or the path (relative to `repo`) of the YAML file
#'   that `config$...` arguments resolve against, at its top level.
#' @param script The targets script.
#' @param repo The project root (a git repository).
#' @param path Where the lock lives, relative to `repo`.
#' @param ref For `read_computation_lock()`, a git ref to read the lock at,
#'   or `NULL` for the working tree.
#' @param lock,baseline Locks as returned by `computation_lock()` or
#'   `read_computation_lock()`.
#' @return `computation_lock()` and `read_computation_lock()` return the lock
#'   as a list; `write_computation_lock()` returns the path invisibly;
#'   `check_computation_lock()` returns `TRUE` invisibly or fails with class
#'   `dctools_lock_mismatch`; `lock_review_table()` returns Markdown lines.
#' @examples
#' \dontrun{
#' links <- data.frame(
#'   decision_id = "D3", decision_status = "approved",
#'   target = "cohort", role = "args"
#' )
#' write_computation_lock(links, config = "config/analysis.yml")
#' check_computation_lock(links, config = "config/analysis.yml")
#' writeLines(lock_review_table(
#'   read_computation_lock(),
#'   baseline = read_computation_lock(ref = "plan-v1")
#' ))
#' }
#' @name computation_lock
NULL

#' @rdname computation_lock
#' @export
computation_lock <- function(
  links,
  config = NULL,
  script = targets::tar_config_get("script"),
  repo = "."
) {
  .require_pkgs(c("targets", "jsonlite"), "computation_lock")
  rows <- .links_block(links)
  config_data <- .read_lock_config(config, repo)
  old_wd <- setwd(repo)
  manifest <- tryCatch(.read_manifest(script), finally = setwd(old_wd))
  commands <- stats::setNames(manifest$command, manifest$name)
  locations <- .target_locations(repo)
  entries <- lapply(rows, function(row) {
    target <- if (is.na(row$target)) NULL else row$target
    entry <- list(
      decision_id = row$decision_id,
      decision_status = row$decision_status,
      target = target,
      role = row$role,
      location = if (is.null(target)) NULL else locations[[target]]
    )
    if (is.null(target)) {
      return(c(entry, list(call = NULL, call_status = "no_target", expression = NULL, arguments = list())))
    }
    if (!target %in% names(commands)) {
      return(c(entry, list(call = NULL, call_status = "missing_target", expression = NULL, arguments = list())))
    }
    c(entry, .lock_call(commands[[target]], config_data, !is.null(config)))
  })
  key <- vapply(entries, function(e) {
    paste(e$decision_id, if (is.null(e$target)) "" else e$target, e$role, sep = "\r")
  }, "")
  list(
    lock_schema_version = .lock_schema_version,
    config = config,
    entries = entries[order(key, method = "radix")]
  )
}

.lock_json <- function(lock) {
  paste0(
    jsonlite::toJSON(
      lock,
      auto_unbox = TRUE,
      pretty = TRUE,
      null = "null",
      na = "null",
      digits = NA
    ),
    "\n"
  )
}

#' @rdname computation_lock
#' @export
write_computation_lock <- function(
  links,
  config = NULL,
  path = "contracts/computation.lock",
  script = targets::tar_config_get("script"),
  repo = "."
) {
  lock <- computation_lock(links, config = config, script = script, repo = repo)
  out <- file.path(repo, path)
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  writeChar(.lock_json(lock), out, eos = NULL, useBytes = TRUE)
  invisible(out)
}

#' @rdname computation_lock
#' @export
read_computation_lock <- function(path = "contracts/computation.lock", ref = NULL, repo = ".") {
  .require_pkgs("jsonlite", "read_computation_lock")
  text <- if (is.null(ref)) {
    paste(readLines(file.path(repo, path), warn = FALSE), collapse = "\n")
  } else {
    paste(.git(repo, c("show", paste0(ref, ":", path))), collapse = "\n")
  }
  jsonlite::fromJSON(text, simplifyVector = FALSE)
}

#' @rdname computation_lock
#' @export
check_computation_lock <- function(
  links,
  config = NULL,
  path = "contracts/computation.lock",
  script = targets::tar_config_get("script"),
  repo = "."
) {
  lock <- computation_lock(links, config = config, script = script, repo = repo)
  expected <- .lock_json(lock)
  file <- file.path(repo, path)
  if (!file.exists(file)) {
    .lock_mismatch(paste0("no committed lock at ", path))
  }
  actual <- readChar(file, file.size(file), useBytes = TRUE)
  if (identical(actual, expected)) {
    return(invisible(TRUE))
  }
  committed <- tryCatch(
    jsonlite::fromJSON(actual, simplifyVector = FALSE),
    error = function(e) NULL
  )
  regenerated <- jsonlite::fromJSON(expected, simplifyVector = FALSE)
  changes <- if (is.null(committed)) {
    "the committed lock is not valid JSON"
  } else {
    rows <- .lock_rows(regenerated, committed)
    rows <- rows[nzchar(rows$change), , drop = FALSE]
    if (nrow(rows)) {
      sprintf("%s / %s / %s: %s", rows$decision, rows$target, rows$setting, rows$change)
    } else {
      "same content, different bytes (the file was not written by write_computation_lock())"
    }
  }
  .lock_mismatch(c(
    paste0(path, " differs from the lock regenerated from source:"),
    utils::head(changes, 20L),
    if (length(changes) > 20L) sprintf("... and %d more", length(changes) - 20L)
  ))
}

.lock_mismatch <- function(lines) {
  stop(structure(
    class = c("dctools_lock_mismatch", "error", "condition"),
    list(message = paste(lines, collapse = "\n"), call = NULL)
  ))
}

.lock_cell_value <- function(arg) {
  status <- arg$status
  if (status %in% c("literal", "config")) {
    v <- jsonlite::toJSON(arg$value, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
    return(as.character(v))
  }
  if (identical(status, "unresolved")) {
    return(sprintf("%s (%s)", arg$expression, arg$reason))
  }
  arg$expression
}

# One row per argument (or per entry with no arguments), with the change
# against `baseline` keyed by decision, target, role and setting.
.lock_rows <- function(lock, baseline = NULL) {
  rows_of <- function(l) {
    if (is.null(l)) {
      return(NULL)
    }
    # Through JSON, so a lock just built and one read from a file compare alike.
    l <- jsonlite::fromJSON(.lock_json(l), simplifyVector = FALSE)
    do.call(rbind, lapply(l$entries, function(e) {
      target <- if (is.null(e$target)) "-" else e$target
      loc <- if (is.null(e$location)) "unknown" else paste0(e$location$file, ":", e$location$line)
      base <- data.frame(
        decision = e$decision_id, target = target, role = e$role, location = loc,
        stringsAsFactors = FALSE
      )
      if (!length(e$arguments)) {
        what <- if (is.null(e$expression)) "" else e$expression
        return(cbind(base, setting = "-", value = what, status = e$call_status))
      }
      do.call(rbind, lapply(e$arguments, function(a) {
        setting <- if (is.null(a$name)) paste0("#", a$position) else a$name
        cbind(base, setting = setting, value = .lock_cell_value(a), status = a$status)
      }))
    }))
  }
  now <- rows_of(lock)
  if (is.null(now)) {
    now <- data.frame(
      decision = character(0), target = character(0), role = character(0),
      location = character(0), setting = character(0), value = character(0),
      status = character(0), stringsAsFactors = FALSE
    )
  }
  now$change <- rep("", nrow(now))
  if (is.null(baseline)) {
    return(now)
  }
  old <- rows_of(baseline)
  key <- function(d) paste(d$decision, d$target, d$role, d$setting, sep = "\r")
  now_key <- key(now)
  old_key <- if (is.null(old)) character(0) else key(old)
  for (i in seq_len(nrow(now))) {
    j <- match(now_key[i], old_key)
    if (is.na(j)) {
      now$change[i] <- "added"
    } else if (!identical(old$value[j], now$value[i]) || !identical(old$status[j], now$status[i])) {
      now$change[i] <- sprintf("changed: %s -> %s", old$value[j], now$value[i])
    }
  }
  gone <- if (is.null(old)) integer(0) else which(!old_key %in% now_key)
  if (length(gone)) {
    removed <- old[gone, , drop = FALSE]
    removed$change <- "removed"
    now <- rbind(now, removed)
  }
  now
}

.md_cell <- function(x) gsub("|", "\\|", x, fixed = TRUE)

#' @rdname computation_lock
#' @export
lock_review_table <- function(lock, baseline = NULL) {
  rows <- .lock_rows(lock, baseline)
  header <- c(
    "| Decision | Target | Location | Setting | Value or expression | Status | Change |",
    "| --- | --- | --- | --- | --- | --- | --- |"
  )
  body <- sprintf(
    "| %s | %s | %s | %s | %s | %s | %s |",
    .md_cell(rows$decision), .md_cell(rows$target), .md_cell(rows$location),
    .md_cell(rows$setting), .md_cell(rows$value), .md_cell(rows$status),
    .md_cell(rows$change)
  )
  c(header, if (nrow(rows)) body)
}
