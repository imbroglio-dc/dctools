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

#' Join with a declared contract and an audit trail
#'
#' A strict-join wrapper: runs a dplyr join with the `relationship` /
#' `unmatched` / `na_matches` contract set explicitly, and returns the joined
#' data with a before/after row-count and match-rate audit trail attached. It
#' turns the merge-time failure [check_unique_id()] cannot see — a join that
#' should be 1:1 but silently inflates rows — into a reported number, or, if you
#' declare `relationship`, an immediate error.
#'
#' `na_matches` defaults to `"never"` (safer than dplyr's `"na"`): two rows with
#' `NA` keys are not the same entity. For a `left`/`inner` join, a grown row
#' count is flagged as a warning — the usual sign of duplicate keys on the right.
#'
#' @param left,right Data frames to join.
#' @param by Character vector of key column name(s), present in both frames.
#' @param type Join type: `"left"` (default), `"inner"`, `"right"`, or `"full"`.
#' @param relationship,unmatched,na_matches Passed to the underlying dplyr join.
#'   `relationship` (e.g. `"one-to-one"`, `"many-to-one"`) errors on violation;
#'   `unmatched` defaults to `"drop"`; `na_matches` defaults to `"never"`.
#' @param quiet Logical; suppress the audit message (the trail is still attached).
#' @return The joined data frame, with a one-row audit data frame attached as
#'   `attr(x, "join_audit")` (columns `type`, `by`, `left_n`, `right_n`,
#'   `joined_n`, `matched_left`, `unmatched_left`, `unmatched_right`,
#'   `match_rate`).
#' @seealso [check_unique_id()] for the single-table key check.
#' @examples
#' left <- data.frame(id = 1:3, x = c("a", "b", "c"))
#' right <- data.frame(id = 1:2, y = c(10, 20))
#' j <- join_audit(left, right, by = "id")
#' attr(j, "join_audit")
#' @export
join_audit <- function(left, right, by,
                       type = c("left", "inner", "right", "full"),
                       relationship = NULL, unmatched = "drop",
                       na_matches = "never", quiet = FALSE) {
  type <- match.arg(type)
  assert_columns(left, by)
  assert_columns(right, by)
  left_n <- nrow(left)
  right_n <- nrow(right)

  join_fn <- switch(type,
    left = dplyr::left_join, inner = dplyr::inner_join,
    right = dplyr::right_join, full = dplyr::full_join
  )
  joined <- join_fn(left, right,
    by = by, relationship = relationship,
    unmatched = unmatched, na_matches = na_matches
  )

  matched_left <- nrow(
    dplyr::semi_join(left, right, by = by, na_matches = na_matches)
  )
  unmatched_right <- nrow(
    dplyr::anti_join(right, left, by = by, na_matches = na_matches)
  )
  joined_n <- nrow(joined)
  match_rate <- if (left_n > 0L) matched_left / left_n else NA_real_

  audit <- data.frame(
    type = type, by = paste(by, collapse = ","),
    left_n = left_n, right_n = right_n, joined_n = joined_n,
    matched_left = matched_left, unmatched_left = left_n - matched_left,
    unmatched_right = unmatched_right, match_rate = match_rate,
    stringsAsFactors = FALSE
  )
  attr(joined, "join_audit") <- audit
  if (!isTRUE(quiet)) .report_join(audit)
  joined
}

.report_join <- function(a) {
  pct <- if (is.na(a$match_rate)) NA else round(100 * a$match_rate, 1)
  fanout <- a$type %in% c("left", "inner") && a$joined_n > a$left_n
  if (isTRUE(fanout)) {
    cli::cli_warn(c(
      "join_audit ({a$type}): row count grew {a$left_n} -> {a$joined_n} (duplicate keys on the right?).",
      "i" = "{pct}% of left keys matched; {a$unmatched_right} right unmatched."
    ))
  } else {
    cli::cli_alert_info(
      "join_audit ({a$type}): {a$joined_n} rows; {pct}% left match ({a$matched_left}/{a$left_n}); {a$unmatched_left} left / {a$unmatched_right} right unmatched."
    )
  }
  invisible(a)
}
