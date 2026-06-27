# PHI-safe output -------------------------------------------------------------

#' Suppress small cells in a summary table
#'
#' Replaces counts in `cols` that fall in `1:(threshold - 1)` with a marker, so
#' aggregate outputs cannot re-identify individuals. Zero is left untouched (a
#' true zero is not disclosive); use `mask_zero = TRUE` to also blank zeros when
#' complementary suppression is a concern.
#'
#' @param data A data frame of *aggregate* counts (never individual-level data).
#' @param cols Columns to screen. Default: all numeric columns.
#' @param threshold Minimum safe cell count (default 11; cells `< threshold` and
#'   `> 0` are suppressed).
#' @param marker Replacement value for suppressed cells (default `"<11"`).
#' @param mask_zero Logical; also suppress exact zeros (default `FALSE`).
#' @return `data` with suppressed cells replaced by `marker` (affected columns
#'   become character).
#' @examples
#' tab <- data.frame(group = c("a", "b"), n = c(3, 42))
#' suppress_small_cells(tab, cols = "n")
#' @export
suppress_small_cells <- function(data, cols = NULL, threshold = 11,
                                 marker = "<11", mask_zero = FALSE) {
  if (is.null(cols)) {
    cols <- names(data)[vapply(data, is.numeric, logical(1))]
  }
  assert_columns(data, cols)
  for (col in cols) {
    v <- data[[col]]
    small <- !is.na(v) & v < threshold & (if (mask_zero) v >= 0 else v > 0)
    if (any(small)) {
      v <- as.character(v)
      v[small] <- marker
      data[[col]] <- v
    }
  }
  data
}
