# Controlled insertion -------------------------------------------------------------
#
# Documents insert reported values only through show_count(), which writes the
# report's masked value inside a span naming its target and id. The rendered
# HTML then carries its own insertion records, and check_rendered_values()
# checks every span against the registry (the stored reports) and flags bare
# numbers outside the spans (architecture section 9).

.display_rules <- "count"
.span_pattern <- paste0(
  "<span class=\"dctools-value\" data-target=\"([^\"]*)\" data-id=\"([^\"]*)\" ",
  "data-rule=\"([^\"]*)\">([^<]*)</span>"
)

.html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}

.html_unescape <- function(x) {
  x <- gsub("&lt;", "<", x, fixed = TRUE)
  x <- gsub("&gt;", ">", x, fixed = TRUE)
  x <- gsub("&quot;", "\"", x, fixed = TRUE)
  x <- gsub("&#39;", "'", x, fixed = TRUE)
  gsub("&amp;", "&", x, fixed = TRUE)
}

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

#' Insert a reported count into a document
#'
#' The controlled display helper for Quarto documents (architecture section
#' 9). It prints a count from a dctools report exactly as the report masks
#' it, and in HTML output wraps it in a span naming the report's target, the
#' count's id and the display rule, so the rendered document carries its
#' own insertion records:
#'
#' ```
#' <span class="dctools-value" data-target="cohort_flow" data-id="n_screened" data-rule="count">412</span>
#' ```
#'
#' [check_rendered_values()] checks every span against the stored reports
#' and flags numbers printed any other way. Use it inline:
#' `` `r dctools::show_count(cohort_flow, "n_screened")` ``, where
#' `cohort_flow <- targets::tar_read(cohort_flow)` loaded the report.
#'
#' @param report A dctools report ([create_report()]).
#' @param id The count's id, as given to [record_count()].
#' @param target The report's target name; defaults to the expression passed
#'   as `report` (so `show_count(cohort_flow, ...)` names `cohort_flow`).
#' @param rule The display rule; only `"count"` (the report's masked value)
#'   in this version.
#' @param format `"auto"` (HTML when knitr is producing HTML), `"html"` or
#'   `"text"`. Text output carries no insertion record, so a non-HTML
#'   document's values cannot be checked.
#' @return The value, as an HTML span or plain text.
#' @seealso [check_rendered_values()].
#' @export
show_count <- function(report, id, target = NULL, rule = "count", format = c("auto", "html", "text")) {
  format <- match.arg(format)
  if (is.null(target)) {
    expr <- substitute(report)
    target <- if (is.name(expr)) as.character(expr) else NA_character_
  }
  if (!inherits(report, "dctools_report")) {
    cli::cli_abort("{.arg report} must be a dctools report.", class = "dctools_display_error")
  }
  if (!is.character(target) || length(target) != 1L || !grepl(.safe_name_pattern, target)) {
    cli::cli_abort("{.arg target} must name the report's target.", class = "dctools_display_error")
  }
  if (!identical(rule, "count")) {
    cli::cli_abort("{.arg rule} must be {.val count}.", class = "dctools_display_error")
  }
  if (!is.character(id) || length(id) != 1L || startsWith(id, "~") || !id %in% names(report$counts)) {
    cli::cli_abort("{.val {id}} is not a printed count of this report.", class = "dctools_display_error")
  }
  value <- .display_count(report, id)
  html <- switch(
    format,
    html = TRUE,
    text = FALSE,
    auto = requireNamespace("knitr", quietly = TRUE) && isTRUE(knitr::is_html_output())
  )
  if (!html) {
    return(value)
  }
  out <- sprintf(
    "<span class=\"dctools-value\" data-target=\"%s\" data-id=\"%s\" data-rule=\"%s\">%s</span>",
    target, .html_escape(id), rule, .html_escape(value)
  )
  if (requireNamespace("knitr", quietly = TRUE)) knitr::asis_output(out) else out
}

# The visible text of an HTML page, with the head, scripts, styles and tags
# removed and each value span replaced by a space.
.visible_text <- function(html) {
  html <- gsub("(?is)<head\\b.*?</head>", " ", html, perl = TRUE)
  html <- gsub("(?is)<(script|style)\\b.*?</\\1>", " ", html, perl = TRUE)
  html <- gsub("(?s)<!--.*?-->", " ", html, perl = TRUE)
  html <- gsub(.span_pattern, " ", html, perl = TRUE)
  .html_unescape(gsub("<[^>]*>", " ", html, perl = TRUE))
}

.default_exemptions <- "^(19|20)[0-9]{2}$"

#' Check a rendered document's values against the stored reports
#'
#' The render check (`render_checked`, architecture section 9) for an HTML
#' document whose values were inserted with [show_count()]. It extracts the
#' insertion records from the page and checks that:
#'
#' * each span names an available report, a printed count of it, the
#'   `count` rule, and shows exactly the value the report prints (masking
#'   recomputed by dctools);
#' * no number appears in the page's visible text outside a span, other
#'   than those matching an `exempt` pattern (by default, years 1900 to
#'   2099). Exemptions are for reviewed constants such as years, citations
#'   and design constants; matching a bare number is never evidence of its
#'   identity.
#'
#' Only HTML is checked; a document in another format is not established.
#'
#' @param path The rendered HTML file.
#' @param reports A named list of dctools reports (target name to report).
#' @param exempt Regular expressions (matched against each whole number)
#'   for numbers allowed outside spans.
#' @return A list: `outcome` (`"pass"`, `"fail"` or `"not_established"`),
#'   `problems`, and `insertions` (one record per span: `index`, `target`,
#'   `id`, `rule`, `display`, `section`, the nearest preceding heading).
#' @seealso [show_count()], [build_release_bundle()].
#' @export
check_rendered_values <- function(path, reports, exempt = .default_exemptions) {
  if (!grepl("\\.html?$", path, ignore.case = TRUE)) {
    return(list(outcome = "not_established", problems = "not an HTML document", insertions = list()))
  }
  if (!file.exists(path)) {
    return(list(outcome = "fail", problems = paste0(path, " does not exist"), insertions = list()))
  }
  html <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  body <- gsub("(?is)<head\\b.*?</head>", " ", html, perl = TRUE)
  m <- gregexpr(.span_pattern, body, perl = TRUE)
  spans <- regmatches(body, m)[[1]]
  starts <- as.integer(m[[1]])
  headings <- gregexpr("(?is)<h[1-3]\\b[^>]*>(.*?)</h[1-3]>", body, perl = TRUE)
  heading_starts <- as.integer(headings[[1]])
  heading_text <- trimws(gsub("\\s+", " ", .html_unescape(gsub("<[^>]*>", " ", regmatches(body, headings)[[1]]))))
  problems <- character(0)
  insertions <- list()
  for (i in seq_along(spans)) {
    parts <- regmatches(spans[i], regexec(.span_pattern, spans[i], perl = TRUE))[[1]]
    target <- parts[2]
    id <- .html_unescape(parts[3])
    rule <- parts[4]
    display <- .html_unescape(parts[5])
    before <- heading_starts[heading_starts >= 0 & heading_starts < starts[i]]
    section <- if (length(before)) heading_text[length(before)] else NA_character_
    insertions[[i]] <- list(index = i, target = target, id = id, rule = rule, display = display, section = section)
    where <- sprintf("value %d (%s / %s)", i, target, id)
    report <- reports[[target]]
    if (!inherits(report, "dctools_report")) {
      problems <- c(problems, paste0(where, ": no available report for target ", target))
    } else if (!rule %in% .display_rules) {
      problems <- c(problems, paste0(where, ": unknown display rule ", rule))
    } else if (startsWith(id, "~") || !id %in% names(report$counts)) {
      problems <- c(problems, paste0(where, ": not a printed count of ", target))
    } else {
      expected <- .display_count(report, id)
      if (!identical(display, expected)) {
        problems <- c(problems, paste0(where, ": shows ", display, ", the report prints ", expected))
      }
    }
  }
  numbers <- .bare_numbers(.visible_text(html))
  allowed <- vapply(numbers, function(n) any(vapply(exempt, function(p) grepl(p, n, perl = TRUE), logical(1))), logical(1))
  for (n in numbers[!allowed]) {
    problems <- c(problems, paste0("bare number ", n, " outside an inserted value"))
  }
  list(outcome = if (length(problems)) "fail" else "pass", problems = problems, insertions = insertions)
}
