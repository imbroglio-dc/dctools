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
    base::getSrcLines(srcfile, srcref[[1]], srcref[[3]]),
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

# requireNamespace (not .require_pkgs) on purpose: no targets means "not in a
# target" (NA), not an error.
.current_target <- function() {
  if (!requireNamespace("targets", quietly = TRUE)) {
    return(NA_character_)
  }
  targets::tar_name(default = NA_character_)
}

# The srcref of the statement, inside the function running in frame `n` (the
# caller), that is evaluating the current call. A call forced lazily as an
# argument of another call (`add_line(r, record_count(r, "n", x))`) has no
# srcref of its own, but the outer call's context carries the statement's.
# Only frames made directly from the caller's own frame count (sys.parents()
# equal to `n`; this includes the block statements of run_section(), which
# are evaluated in the caller's environment), and the srcref must lie in the
# caller function's own file and line span. If the caller has no source
# references, or nothing matches, the result is NULL: never a guess.
# Must be called with `n` an absolute frame index (from .frame_of()).
.enclosing_srcref <- function(n) {
  fn_srcref <- attr(sys.function(n), "srcref")
  if (is.null(fn_srcref)) {
    return(NULL)
  }
  fn_file <- .srcref_path(fn_srcref)
  if (is.na(fn_file)) {
    return(NULL)
  }
  calls <- sys.calls()
  parents <- sys.parents()
  for (k in rev(seq_along(calls))) {
    if (k <= n || parents[[k]] != n) {
      next
    }
    srcref <- attr(calls[[k]], "srcref")
    if (
      !is.null(srcref) &&
        identical(.srcref_path(srcref), fn_file) &&
        srcref[[1]] >= fn_srcref[[1]] &&
        srcref[[3]] <= fn_srcref[[3]]
    ) {
      return(srcref)
    }
  }
  NULL
}

# Whether `srcref` is verified to lie in the source file and line span of the
# function running in frame `n`. Fails closed: FALSE when that function has no
# usable file span to compare against, since the srcref may then point into
# other code (dctools itself, for a call forced inside run_section()).
.within_function <- function(srcref, n) {
  fn_srcref <- attr(sys.function(n), "srcref")
  if (is.null(fn_srcref) || is.na(.srcref_path(fn_srcref))) {
    return(FALSE)
  }
  identical(.srcref_path(srcref), .srcref_path(fn_srcref)) &&
    srcref[[1]] >= fn_srcref[[1]] &&
    srcref[[3]] <= fn_srcref[[3]]
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
  n <- .frame_of(env)
  # A call evaluated lazily inside another function (a promise forced in
  # run_section(), say) carries the srcref of the forcing statement, which may
  # lie in other code (dctools itself under load_all()). Only the caller's own
  # statements count.
  if (!is.null(srcref) && !is.na(n) && n > 0L && !.within_function(srcref, n)) {
    srcref <- NULL
  }
  if (is.null(srcref) && !is.na(n) && n > 0L) {
    srcref <- .enclosing_srcref(n)
  }
  if (!is.null(srcref)) {
    out$file <- .srcref_path(srcref)
    # Lines of parsed text (no file) mean nothing to a reader: leave them NA.
    if (!is.na(out$file)) {
      out$line_start <- as.integer(srcref[[1]])
      out$line_end <- as.integer(srcref[[3]])
      out$code <- .srcref_lines(srcref)
    }
  }
  if (!is.na(n) && n > 0L) {
    out$function_name <- .call_name(sys.call(n))
    fn_srcref <- attr(sys.function(n), "srcref")
    if (!is.null(fn_srcref)) {
      out$function_file <- .srcref_path(fn_srcref)
      if (!is.na(out$function_file)) {
        out$function_line_start <- as.integer(fn_srcref[[1]])
        out$function_line_end <- as.integer(fn_srcref[[3]])
        out$function_name <- .definition_name(fn_srcref, out$function_name)
      }
    }
  }
  out
}

# The function definitions of the source files seen so far, kept with the
# lines they were parsed from (a file sourced again after an edit is
# re-parsed).
.defs_cache <- new.env(parent = emptyenv())

# The name a function is defined under in its source (`helper <- function`),
# whatever it was called as (lapply() calls it FUN); "(anonymous function)"
# when the source shows no name; `fallback` when the source cannot be read.
.definition_name <- function(fn_srcref, fallback) {
  srcfile <- attr(fn_srcref, "srcfile")
  path <- .srcref_path(fn_srcref)
  lines <- tryCatch(
    base::getSrcLines(srcfile, 1L, .Machine$integer.max),
    error = function(e) character(0)
  )
  if (is.na(path) || !length(lines)) {
    return(fallback)
  }
  hit <- .defs_cache[[path]]
  if (is.null(hit) || !identical(hit$lines, lines)) {
    hit <- list(lines = lines, defs = .function_defs(lines))
    assign(path, hit, envir = .defs_cache)
  }
  defs <- hit$defs
  row <- defs[
    defs$line_start == fn_srcref[[1]] &
      defs$col_start == fn_srcref[[5]] &
      defs$line_end == fn_srcref[[3]],
    ,
    drop = FALSE
  ]
  if (nrow(row) != 1L) {
    return(fallback)
  }
  if (is.na(row$name[[1]])) "(anonymous function)" else row$name[[1]]
}

# Attach a provenance record to a registered count id.
.store_provenance <- function(report, id, provenance) {
  report$provenance[[id]] <- c(list(id = id), provenance)
  invisible(NULL)
}

# Bare-number guard ------------------------------------------------------------
#
# A number printed without record_count() has no provenance. Text added to a
# report may contain digits only inside {{placeholders}}, right after a letter
# or underscore (J7, death_28d, D13, n42), or as constants written in the
# source of the call that added the text. Digits followed by letters ("64d",
# "45min") or after a dot (".031") are bare numbers. Anything else is recorded
# by location only: the number itself may be a patient-level value.

.bare_numbers <- function(text) {
  text <- text[!is.na(text)]
  if (!length(text)) {
    return(character(0))
  }
  text <- gsub(.placeholder_pattern, " ", paste(text, collapse = "\n"))
  m <- gregexpr(
    "(?<![A-Za-z0-9_])[0-9]+(\\.[0-9]+)?",
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
  provenance <- .capture_provenance(call, env)
  if (all(numbers %in% .bare_numbers(provenance$code))) {
    return(invisible(FALSE))
  }
  report$unprovenanced[[length(report$unprovenanced) + 1L]] <- provenance
  invisible(TRUE)
}
