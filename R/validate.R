# Data validation -------------------------------------------------------------

#' Assert that required columns are present
#'
#' Errors (via [cli::cli_abort()]) if any of `cols` is missing from `data`,
#' naming the offenders. Invisibly returns `data` so it can be used inline in a
#' pipe.
#'
#' @param data A data frame.
#' @param cols Character vector of required column names.
#' @return `data`, invisibly.
#' @examples
#' df <- data.frame(id = 1:3, age = c(40, 50, 60))
#' assert_columns(df, c("id", "age"))
#' @export
assert_columns <- function(data, cols) {
  missing <- setdiff(cols, names(data))
  if (length(missing) > 0L) {
    cli::cli_abort(c(
      "{.arg data} is missing required column{?s}: {.val {missing}}.",
      "i" = "Present columns: {.val {names(data)}}."
    ))
  }
  invisible(data)
}

#' Check that a column (or set of columns) uniquely identifies rows
#'
#' @param data A data frame.
#' @param id Character vector of key column name(s).
#' @param error Logical; if `TRUE` (default) abort on duplicates, otherwise warn
#'   and return the duplicated keys.
#' @return Invisibly, a data frame of duplicated keys with their counts (empty
#'   when the key is unique).
#' @examples
#' df <- data.frame(id = c(1, 1, 2), x = 1:3)
#' check_unique_id(df, "id", error = FALSE)
#' @export
check_unique_id <- function(data, id, error = TRUE) {
  assert_columns(data, id)
  counts <- dplyr::count(data, dplyr::across(dplyr::all_of(id)), name = "n_rows")
  dupes <- counts[counts[["n_rows"]] > 1L, , drop = FALSE]
  if (nrow(dupes) > 0L) {
    msg <- "{.arg id} ({.val {id}}) does not uniquely identify rows: {nrow(dupes)} duplicated key{?s}."
    if (isTRUE(error)) cli::cli_abort(msg) else cli::cli_warn(msg)
  }
  invisible(dupes)
}

#' Flag values outside an expected numeric range
#'
#' Returns the indices (and values) of `x` that fall below `lo` or above `hi`.
#' Useful for codebook range checks during data cleaning. `NA` values are
#' ignored.
#'
#' @param x Numeric vector.
#' @param lo,hi Inclusive lower/upper bounds. Use `-Inf`/`Inf` to disable a side.
#' @param label Optional name for messaging.
#' @return Invisibly, a data frame with columns `index` and `value` for each
#'   out-of-range element (empty when all in range).
#' @examples
#' flag_out_of_range(c(5, 200, NA, -1), lo = 0, hi = 100, label = "sbp")
#' @export
flag_out_of_range <- function(x, lo = -Inf, hi = Inf, label = NULL) {
  oor <- which(!is.na(x) & (x < lo | x > hi))
  if (length(oor) > 0L) {
    nm <- if (is.null(label)) "values" else label
    cli::cli_warn("{length(oor)} {nm} outside [{lo}, {hi}].")
  }
  invisible(data.frame(index = oor, value = x[oor]))
}
