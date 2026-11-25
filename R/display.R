# Display of reported counts ---------------------------------------------------

# The value a report prints for `id`, with masking recomputed by dctools (a
# resolver stored in the object could be stale).
.display_count <- function(report, id) {
  fresh <- new.env(parent = emptyenv())
  for (nm in ls(report, all.names = TRUE)) {
    assign(nm, get(nm, envir = report), envir = fresh)
  }
  class(fresh) <- class(report)
  fresh$resolver <- NULL
  fresh$decision <- NULL
  fresh$is_rendered <- FALSE
  .resolve_value(fresh, id)
}

#' Print a count from a report as the report masks it
#'
#' Returns one printed count of a dctools report as text, exactly as the
#' report masks it (masking recomputed by dctools, not taken from a resolver
#' stored in the object). For example, `show_count(cohort_flow, "n_excluded")`
#' gives `"<5"` when the count is below the report's threshold.
#'
#' @param report A dctools report ([create_report()]).
#' @param id The count's id, as given to [record_count()].
#' @return The masked value, a character string.
#' @export
show_count <- function(report, id) {
  if (!inherits(report, "dctools_report")) {
    cli::cli_abort("{.arg report} must be a dctools report.", class = "dctools_display_error")
  }
  if (!is.character(id) || length(id) != 1L || startsWith(id, "~") || !id %in% names(report$counts)) {
    cli::cli_abort("{.val {id}} is not a printed count of this report.", class = "dctools_display_error")
  }
  .display_count(report, id)
}
