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
#' which also record the source lines that computed each one. Editing the
#' report's internal fields directly (its counts, provenance or output) is
#' not detected by the audit; it is a matter for code review.
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

.count_id_pattern <- "^~?[A-Za-z][A-Za-z0-9_.]*$"

# Ids reach the ledger, the audit pages and C8's details, so they are
# identifier-like: a letter, then letters, digits, "_" or "." ("~" first for
# an unprinted quantity).
.check_count_id <- function(id) {
  if (
    !is.character(id) ||
      length(id) != 1L ||
      is.na(id) ||
      !grepl(.count_id_pattern, id)
  ) {
    cli::cli_abort(
      c(
        "A count id must be one string matching {.code {(.count_id_pattern)}}.",
        "i" = "Start with a letter; use letters, digits, {.code _} and {.code .}."
      ),
      class = "dctools_report_id_error"
    )
  }
  invisible(id)
}

# The fields that say where a value was recorded.
.same_site <- function(a, b) {
  fields <- c("file", "line_start", "line_end", "function_name")
  identical(a[fields], b[fields])
}

# Registering an existing id with a different value, or from a different site
# (`provenance`), creates a new id ("id_2", ...) instead of overwriting.
# Returns the id used.
.register_count <- function(
  report,
  id,
  value,
  protect = FALSE,
  provenance = NULL
) {
  .stop_if_prepared(report)
  value <- as.numeric(value)
  base_id <- id
  suffix <- 1L
  other_site <- function(id) {
    known <- report$provenance[[id]]
    !is.null(provenance) && !is.null(known) && !.same_site(known, provenance)
  }
  while (
    id %in%
      names(report$counts) &&
      (!isTRUE(all.equal(report$counts[[id]], value)) || other_site(id))
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
#' `keep.source = TRUE`). This is how numbers enter a report; direct edits
#' of the report's internal fields bypass it and are not detected.
#'
#' @param report A report from [create_report()].
#' @param id The count's id: a letter, then letters, digits, `_` or `.`
#'   (anything else is an error of class `dctools_report_id_error`). If `id`
#'   is already registered with a different value, or from another line of
#'   code, `"id_2"`, `"id_3"`, ... is used instead.
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
  call <- sys.call()
  env <- parent.frame()
  .check_count_id(id)
  provenance <- .capture_provenance(call, env)
  id <- .register_count(report, id, expr, protect, provenance)
  .store_provenance(report, id, provenance)
  paste0("{{", id, "}}")
}

#' Record a quantity used in relations but never printed
#'
#' @param report A report from [create_report()].
#' @param id The quantity's id: `"~"`, a letter, then letters, digits, `_`
#'   or `.`.
#' @param expr The expression computing it.
#' @return `id`, invisibly.
#' @seealso [declare_linear_relation()].
#' @examples
#' r <- create_report()
#' record_unprinted_count(r, "~excluded", 3)
#' @export
record_unprinted_count <- function(report, id, expr) {
  call <- sys.call()
  env <- parent.frame()
  .stop_if_prepared(report)
  .check_count_id(id)
  stopifnot(startsWith(id, "~"))
  report$unprinted_counts[id] <- as.numeric(expr)
  .store_provenance(report, id, .capture_provenance(call, env))
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
  .check_bare_numbers(report, text, sys.call(), parent.frame())
  .add_output_step(report, function(resolve) cat(resolve(text), "\n", sep = ""))
}

#' @rdname add_line
#' @param text A line printed with no placeholder parsing.
#' @export
add_literal_line <- function(report, text) {
  force(text)
  .check_bare_numbers(report, text, sys.call(), parent.frame())
  .add_output_step(report, function(resolve) cat(text, "\n", sep = ""))
}

#' @rdname add_line
#' @param data A data frame; every cell is printed as text.
#' @export
add_data_frame <- function(report, data) {
  force(data)
  .check_bare_numbers(
    report,
    c(names(data), unlist(lapply(data, as.character), use.names = FALSE)),
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

# Labels that come from data print only if they are short and identifier-like
# and hold no bare number (an age, a date): digits are allowed only right
# after a letter or underscore, as in "J7" or "a_1".
.sanitize_labels <- function(labels) {
  has_number <- vapply(
    labels,
    function(l) length(.bare_numbers(l)) > 0L,
    logical(1),
    USE.NAMES = FALSE
  )
  ifelse(
    is.na(labels),
    NA_character_,
    ifelse(
      grepl("^[A-Za-z0-9_ .-]{1,20}$", labels) & !has_number,
      labels,
      "<other>"
    )
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
  .check_count_id(id)
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
    cell_ids[i] <- .register_count(
      report,
      cell_ids[i],
      counts[i],
      protect,
      provenance
    )
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
#' @param id Prefix of the cell ids (`"<id>.1"`, `"<id>.2"`, ...); a letter,
#'   then letters, digits, `_` or `.`.
#' @param expr For `add_count_table()`, an expression giving a table (or
#'   array) of counts; for `add_tabulation()`, a vector to tabulate.
#' @param protect Keep the cells visible if at all possible.
#' @param labels_from_code `TRUE` when the dimension labels are constants in
#'   the code; they are then printed as they are, outside any protection.
#'   Otherwise (the default) a label that is not short and identifier-like,
#'   or that holds a bare number (`"31"`, `"1985-03-12"`; digits right after a
#'   letter or underscore, as in `"J7"`, are allowed), prints as `"<other>"`.
#' @param total_id `NULL` or the id of a registered count equal to the sum of
#'   all cells.
#' @param max_levels The largest number of levels a printed dimension may
#'   have.
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

#' @rdname add_count_table
#' @export
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
  if (heading) {
    .check_bare_numbers(report, title, sys.call(), parent.frame())
  }
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
