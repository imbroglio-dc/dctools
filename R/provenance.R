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
    # Lines of parsed text (no file) mean nothing to a reader: leave them NA.
    if (!is.na(out$file)) {
      out$line_start <- as.integer(srcref[[1]])
      out$line_end <- as.integer(srcref[[3]])
      out$code <- .srcref_lines(srcref)
    }
  }
  n <- .frame_of(env)
  if (!is.na(n) && n > 0L) {
    out$function_name <- .call_name(sys.call(n))
    fn_srcref <- attr(sys.function(n), "srcref")
    if (!is.null(fn_srcref)) {
      out$function_file <- .srcref_path(fn_srcref)
      if (!is.na(out$function_file)) {
        out$function_line_start <- as.integer(fn_srcref[[1]])
        out$function_line_end <- as.integer(fn_srcref[[3]])
      }
    }
  }
  out
}

# Attach a provenance record to a registered count id.
.store_provenance <- function(report, id, provenance) {
  report$provenance[[id]] <- c(list(id = id), provenance)
  invisible(NULL)
}
