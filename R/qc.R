# Data-intake QC ---------------------------------------------------------------

#' Detect disguised-missing sentinel values
#'
#' Scans for values that commonly encode missingness but are not stored as `NA`:
#' numeric codes (e.g. `-9`, `999`) and string tokens (e.g. `""`, `"N/A"`,
#' `"unknown"`, whitespace-only). Never modifies the data; returns a report so
#' you can decide what to convert.
#'
#' @param data A data frame.
#' @param numeric_codes Numeric vector of suspect codes.
#' @param string_tokens Character vector of suspect tokens (compared after
#'   trimming whitespace).
#' @param ignore_case Logical; case-insensitive token matching (default `TRUE`).
#' @return A data frame with one row per column/sentinel found: `column`,
#'   `type`, `sentinel`, `n`, `prop`.
#' @export
detect_missing_sentinels <- function(data,
                                     numeric_codes = c(-9, -99, -999, -9999, 99, 999, 9999),
                                     string_tokens = c("", "NA", "N/A", ".", "null", "none",
                                                       "missing", "unknown", "-", "--"),
                                     ignore_case = TRUE) {
  out <- list()
  for (col in names(data)) {
    v <- data[[col]]
    n <- length(v)
    if (n == 0L) next
    if (is.numeric(v)) {
      for (code in numeric_codes) {
        cnt <- sum(v == code, na.rm = TRUE)
        if (cnt > 0L) {
          out[[length(out) + 1L]] <- data.frame(
            column = col, type = "numeric", sentinel = as.character(code),
            n = cnt, prop = cnt / n, stringsAsFactors = FALSE
          )
        }
      }
    } else if (is.character(v) || is.factor(v)) {
      cmp <- trimws(as.character(v))
      toks <- string_tokens
      if (isTRUE(ignore_case)) {
        cmp <- tolower(cmp)
        toks <- tolower(string_tokens)
      }
      for (i in seq_along(string_tokens)) {
        cnt <- sum(!is.na(cmp) & cmp == toks[i])
        if (cnt > 0L) {
          out[[length(out) + 1L]] <- data.frame(
            column = col, type = "character", sentinel = string_tokens[i],
            n = cnt, prop = cnt / n, stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  if (length(out) == 0L) {
    return(data.frame(column = character(), type = character(),
                      sentinel = character(), n = integer(), prop = double()))
  }
  do.call(rbind, out)
}

#' Flag problematic column names
#'
#' Reports columns whose names are empty, non-syntactic, contain whitespace or
#' leading/trailing spaces, contain non-ASCII characters, are duplicated, or
#' collide with another name only by case.
#'
#' @param data A data frame.
#' @return A data frame with `column` and a comma-separated `issues` string,
#'   one row per problematic name (empty when all names are clean).
#' @export
check_colnames <- function(data) {
  nm <- names(data)
  lower <- tolower(nm)
  case_dup <- lower %in% lower[duplicated(lower)]
  rows <- list()
  for (i in seq_along(nm)) {
    x <- nm[i]
    iss <- character(0)
    if (is.na(x) || x == "") iss <- c(iss, "empty")
    if (!is.na(x) && nzchar(x) && x != make.names(x)) iss <- c(iss, "non-syntactic")
    if (!is.na(x) && grepl("\\s", x)) iss <- c(iss, "whitespace")
    if (!is.na(x) && x != trimws(x)) iss <- c(iss, "leading/trailing space")
    if (!is.na(x) && grepl("[^\\x01-\\x7F]", x, perl = TRUE)) iss <- c(iss, "non-ASCII")
    if (sum(nm == x) > 1L) iss <- c(iss, "duplicated")
    if (case_dup[i] && sum(nm == x) == 1L) iss <- c(iss, "case-collision")
    if (length(iss) > 0L) {
      rows[[length(rows) + 1L]] <- data.frame(
        column = x, issues = paste(iss, collapse = ", "), stringsAsFactors = FALSE
      )
    }
  }
  if (length(rows) == 0L) return(data.frame(column = character(), issues = character()))
  do.call(rbind, rows)
}

#' Clean column names to snake_case
#'
#' Splits camelCase, lower-cases, replaces runs of non-alphanumeric characters
#' with `_`, trims, and de-duplicates. The before/after map is attached as the
#' `"colname_map"` attribute.
#'
#' @param data A data frame.
#' @return `data` with cleaned names and a `"colname_map"` attribute.
#' @export
clean_colnames <- function(data) {
  old <- names(data)
  new <- gsub("([a-z0-9])([A-Z])", "\\1_\\2", old)
  new <- tolower(new)
  new <- gsub("[^a-z0-9]+", "_", new)
  new <- gsub("_+", "_", new)
  new <- gsub("^_|_$", "", new)
  new <- make.unique(new, sep = "_")
  names(data) <- new
  if (any(old != new)) cli::cli_inform("Renamed {sum(old != new)} column{?s}.")
  attr(data, "colname_map") <- data.frame(old = old, new = new, stringsAsFactors = FALSE)
  data
}

#' Heuristically flag likely column-type problems
#'
#' Conservative checks that surface common typing issues for review: text that
#' parses as numeric or as dates, two-valued text that is really logical,
#' high-cardinality text, and numeric columns that are really binary.
#'
#' @param data A data frame.
#' @param max_factor_levels Above this many unique values, text is flagged as
#'   high-cardinality (default 50).
#' @return A data frame: `column`, `stored_type`, `issue`, `detail` (one row per
#'   finding; empty when nothing is flagged).
#' @export
check_types <- function(data, max_factor_levels = 50) {
  out <- list()
  for (col in names(data)) {
    v <- data[[col]]
    st <- class(v)[1]
    if (is.character(v) || is.factor(v)) {
      cv <- as.character(v)
      nonmiss <- cv[!is.na(cv) & trimws(cv) != ""]
      if (length(nonmiss) > 0L) {
        cleaned <- gsub("[ ,%]", "", nonmiss)
        num_ok <- suppressWarnings(!is.na(as.numeric(cleaned)))
        if (mean(num_ok) >= 0.95) {
          out[[length(out) + 1L]] <- data.frame(
            column = col, stored_type = st, issue = "numeric stored as text",
            detail = sprintf("%.0f%% parse as numeric", 100 * mean(num_ok)),
            stringsAsFactors = FALSE
          )
        }
        date_ok <- grepl("^\\d{4}[-/]\\d{1,2}[-/]\\d{1,2}$", nonmiss) |
          grepl("^\\d{1,2}[-/]\\d{1,2}[-/]\\d{4}$", nonmiss)
        if (mean(date_ok) >= 0.95) {
          out[[length(out) + 1L]] <- data.frame(
            column = col, stored_type = st, issue = "date stored as text",
            detail = "matches a date pattern", stringsAsFactors = FALSE
          )
        }
        lvls <- tolower(unique(nonmiss))
        if (all(lvls %in% c("y", "n", "yes", "no", "true", "false", "t", "f"))) {
          out[[length(out) + 1L]] <- data.frame(
            column = col, stored_type = st, issue = "logical stored as text",
            detail = paste(unique(nonmiss), collapse = "/"), stringsAsFactors = FALSE
          )
        }
      }
      nu <- length(unique(nonmiss))
      if (nu > max_factor_levels) {
        out[[length(out) + 1L]] <- data.frame(
          column = col, stored_type = st, issue = "high-cardinality",
          detail = sprintf("%d unique values", nu), stringsAsFactors = FALSE
        )
      }
    } else if (is.numeric(v)) {
      u <- unique(v[!is.na(v)])
      if (length(u) > 0L && all(u %in% c(0, 1))) {
        out[[length(out) + 1L]] <- data.frame(
          column = col, stored_type = st, issue = "binary stored as numeric",
          detail = "only 0/1 - consider logical or factor", stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(out) == 0L) {
    return(data.frame(column = character(), stored_type = character(),
                      issue = character(), detail = character()))
  }
  do.call(rbind, out)
}

#' Identify constant or all-missing columns
#'
#' @param data A data frame.
#' @return A data frame: `column`, `issue` ("all missing" or "constant"),
#'   `n_unique` (non-missing unique values). Empty when none.
#' @export
check_constant_cols <- function(data) {
  rows <- list()
  for (col in names(data)) {
    v <- data[[col]]
    if (all(is.na(v))) {
      rows[[length(rows) + 1L]] <- data.frame(
        column = col, issue = "all missing", n_unique = 0L, stringsAsFactors = FALSE
      )
    } else {
      nu <- length(unique(v[!is.na(v)]))
      if (nu <= 1L) {
        rows[[length(rows) + 1L]] <- data.frame(
          column = col, issue = "constant", n_unique = nu, stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(rows) == 0L) {
    return(data.frame(column = character(), issue = character(), n_unique = integer()))
  }
  do.call(rbind, rows)
}

#' Find highly correlated numeric column pairs
#'
#' Pairwise Pearson correlation across numeric columns, returning pairs at or
#' above `threshold` in absolute value, sorted by strength. A first-pass
#' redundancy screen (extend with VIF / Cramer's V as needed).
#'
#' @param data A data frame.
#' @param threshold Absolute correlation cutoff (default 0.9).
#' @return A data frame: `col1`, `col2`, `correlation`, sorted by `abs()`.
#'   Empty when fewer than two numeric columns or no pair qualifies.
#' @export
check_collinearity <- function(data, threshold = 0.9) {
  num <- data[vapply(data, is.numeric, logical(1))]
  empty <- data.frame(col1 = character(), col2 = character(), correlation = double())
  if (ncol(num) < 2L) return(empty)
  cm <- suppressWarnings(stats::cor(num, use = "pairwise.complete.obs"))
  cols <- colnames(cm)
  out <- list()
  for (i in seq_len(ncol(cm) - 1L)) {
    for (j in (i + 1L):ncol(cm)) {
      r <- cm[i, j]
      if (!is.na(r) && abs(r) >= threshold) {
        out[[length(out) + 1L]] <- data.frame(
          col1 = cols[i], col2 = cols[j], correlation = r, stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(out) == 0L) return(empty)
  res <- do.call(rbind, out)
  res[order(-abs(res$correlation)), , drop = FALSE]
}

#' One-call cohort QC description
#'
#' Bundles a per-column overview with the QC screens (`check_colnames`,
#' `check_types`, `check_constant_cols`, `detect_missing_sentinels`,
#' `check_collinearity`) into a single structured report. Suitable for diffing
#' across data refreshes.
#'
#' @param data A data frame.
#' @return A named list: `dims`, `overview`, `colname_issues`, `type_issues`,
#'   `constant_cols`, `missing_sentinels`, `collinearity`.
#' @export
describe_cohort <- function(data) {
  overview <- data.frame(
    column = names(data),
    type = vapply(data, function(x) class(x)[1], character(1)),
    n_missing = vapply(data, function(x) sum(is.na(x)), integer(1)),
    prop_missing = vapply(data, function(x) mean(is.na(x)), double(1)),
    n_unique = vapply(data, function(x) length(unique(x)), integer(1)),
    row.names = NULL, stringsAsFactors = FALSE
  )
  list(
    dims = c(rows = nrow(data), cols = ncol(data)),
    overview = overview,
    colname_issues = check_colnames(data),
    type_issues = check_types(data),
    constant_cols = check_constant_cols(data),
    missing_sentinels = detect_missing_sentinels(data),
    collinearity = check_collinearity(data)
  )
}
